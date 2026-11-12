# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Authn::IamReplication::OauthAccessTokenReplicator, feature_category: :system_access do
  using RSpec::Parameterized::TableSyntax

  let_it_be(:application) { create(:oauth_application) }

  let(:client) { instance_double(Authn::IamService::GrpcClient, upsert_oauth_refresh_token: nil) }

  subject(:replicator) { described_class.new(client: client) }

  describe '.reconciliation_scope' do
    it 'returns only tokens with a refresh token' do
      token = create(:oauth_access_token, application: application)
      create(:oauth_access_token, application: application, refresh_token: nil)

      expect(described_class.reconciliation_scope).to contain_exactly(token)
    end

    it 'excludes tokens without an application' do
      token = create(:oauth_access_token, application: application)
      create(:oauth_access_token, application: application).update_column(:application_id, nil)

      expect(described_class.reconciliation_scope).to contain_exactly(token)
    end

    it 'excludes tokens revoked before the revocation cutoff' do
      live_token = create(:oauth_access_token, application: application)
      revoked_after_cutoff = create(:oauth_access_token,
        application: application, revoked_at: described_class::REVOCATION_CUTOFF + 1.day)
      create(:oauth_access_token, application: application, revoked_at: described_class::REVOCATION_CUTOFF - 1.day)

      expect(described_class.reconciliation_scope).to contain_exactly(live_token, revoked_after_cutoff)
    end
  end

  describe '#upsert' do
    let_it_be(:user) { create(:user) }
    let_it_be(:token) do
      create(:oauth_access_token,
        application: application, resource_owner: user, scopes: 'api read_user', use_refresh_token: true)
    end

    it 'pushes the full field set to IAM and returns :delivered', :aggregate_failures do
      expect(replicator.upsert(token)).to eq(:delivered)
      expect(client).to have_received(:upsert_oauth_refresh_token).once.with(
        signature: token.refresh_token,
        client_id: application.uid,
        subject: user.id.to_s,
        scopes: %w[api read_user],
        revoked_at: nil,
        created_at: Google::Protobuf::Timestamp.new(seconds: token.created_at.to_i),
        owning_cell_id: Gitlab.config.cell.id.to_i,
        source_id: token.id
      )
    end

    context 'with a different configured cell' do
      before do
        stub_config_cell(id: 7)
      end

      it 'sends the configured owning_cell_id' do
        replicator.upsert(token)

        expect(client).to have_received(:upsert_oauth_refresh_token).with(hash_including(owning_cell_id: 7))
      end
    end

    context 'when IAM fails' do
      before do
        allow(client).to receive(:upsert_oauth_refresh_token)
          .and_raise(Authn::IamService::GrpcClient::RequestError.new('down', reason: :unavailable))
      end

      it 'raises' do
        expect { replicator.upsert(token) }.to raise_error(Authn::IamService::GrpcClient::RequestError)
      end
    end

    context 'when the application of the token was deleted' do
      let_it_be(:orphan_application) { create(:oauth_application) }
      let_it_be_with_reload(:orphan_token) { create(:oauth_access_token, application: orphan_application) }

      before do
        orphan_application.delete
      end

      it 'returns :skipped without calling IAM', :aggregate_failures do
        expect(replicator.upsert(orphan_token)).to eq(:skipped)
        expect(client).not_to have_received(:upsert_oauth_refresh_token)
      end
    end

    context 'when the stored refresh token is not a supported digest' do
      let(:token_with_stored_value) do
        create(:oauth_access_token, application: application).tap { |t| t.update_column(:refresh_token, 'test-token') }
      end

      it 'sends its SHA-512 digest as signature' do
        replicator.upsert(token_with_stored_value)

        expect(client).to have_received(:upsert_oauth_refresh_token)
          .with(hash_including(signature: Gitlab::DoorkeeperSecretStoring::Sha512Hash.transform_secret('test-token')))
      end
    end

    context 'when the token is revoked' do
      let_it_be(:revoked_token) do
        create(:oauth_access_token, application: application, revoked_at: 1.minute.ago, use_refresh_token: true)
      end

      it 'sends revoked_at' do
        replicator.upsert(revoked_token)

        expect(client).to have_received(:upsert_oauth_refresh_token).with(
          hash_including(revoked_at: Google::Protobuf::Timestamp.new(seconds: revoked_token.revoked_at.to_i))
        )
      end
    end
  end

  describe '#deliver' do
    let_it_be(:token) { create(:oauth_access_token, application: application) }

    context 'with an upsert event' do
      let(:row) { build(:iam_outbox, entity_type: 'oauth_access_token', entity_id: token.id) }

      it 'upserts the token and returns :delivered', :aggregate_failures do
        expect(replicator.deliver(row)).to eq(:delivered)
        expect(client).to have_received(:upsert_oauth_refresh_token).with(hash_including(source_id: token.id))
      end

      context 'when the Rails record is absent' do
        let(:row) { build(:iam_outbox, entity_type: 'oauth_access_token', entity_id: non_existing_record_id) }

        it 'returns :skipped without calling IAM', :aggregate_failures do
          expect(replicator.deliver(row)).to eq(:skipped)
          expect(client).not_to have_received(:upsert_oauth_refresh_token)
        end
      end
    end

    context 'with a delete event' do
      let(:row) do
        build(:iam_outbox, entity_type: 'oauth_access_token', event_type: :delete,
          payload: { 'owning_cell_id' => 1, 'source_id' => 5 })
      end

      it 'returns :skipped without calling IAM', :aggregate_failures do
        expect(replicator.deliver(row)).to eq(:skipped)
        expect(client).not_to have_received(:upsert_oauth_refresh_token)
      end
    end

    context 'with an event_type the replicator does not handle' do
      let(:row) { instance_double(Authn::IamOutbox, event_type: 'unknown') }

      it 'raises' do
        expect { replicator.deliver(row) }.to raise_error(ArgumentError, /unhandled event_type/)
      end
    end
  end

  describe '#bulk_upsert' do
    let_it_be(:tokens) { create_list(:oauth_access_token, 2, application: application, use_refresh_token: true) }

    def response(*results)
      ::Gitlab::Iam::Auth::V1::InternalOAuthDoorkeeperRefreshTokensServiceBulkUpsertResponse.new(results: results)
    end

    before do
      allow(client).to receive(:bulk_upsert_oauth_refresh_tokens)
        .and_return(response({ reason: :REASON_WRITTEN }, { reason: :REASON_WRITTEN }))
    end

    it 'sends every token in one call' do
      replicator.bulk_upsert(tokens)

      expect(client).to have_received(:bulk_upsert_oauth_refresh_tokens).once.with(tokens: [
        hash_including(signature: tokens.first.refresh_token, client_id: application.uid, source_id: tokens.first.id),
        hash_including(source_id: tokens.second.id)
      ])
    end

    context 'when IAM refuses a token' do
      where(:reason, :outcome) do
        :REASON_CLIENT_NOT_FOUND | :failed_precondition
        :REASON_CLIENT_MISMATCH  | :invalid_request
        :REASON_INVALID          | :invalid_request
        :REASON_DUPLICATE        | :invalid_request
        :REASON_UNSPECIFIED      | :invalid_request
      end

      with_them do
        before do
          allow(client).to receive(:bulk_upsert_oauth_refresh_tokens)
            .and_return(response({ reason: reason, message: 'msg' }, { reason: :REASON_WRITTEN, message: '' }))
        end

        it 'returns the outcome, the IAM message and the IAM reason for each token' do
          expect(replicator.bulk_upsert(tokens)).to contain_exactly(
            [tokens.first, outcome, 'msg', reason.to_s],
            [tokens.second, :delivered, nil, 'REASON_WRITTEN']
          )
        end
      end
    end

    context 'when the application of a token was deleted' do
      let_it_be(:orphan_application) { create(:oauth_application) }
      let_it_be_with_reload(:orphan_token) { create(:oauth_access_token, application: orphan_application) }

      before do
        # By id: the shared record stays marked destroyed after the first example, so #delete would do nothing.
        orphan_application.class.delete(orphan_application.id)
      end

      it 'maps results to the sent tokens when some are skipped', :aggregate_failures do
        allow(client).to receive(:bulk_upsert_oauth_refresh_tokens)
          .and_return(response({ reason: :REASON_INVALID, message: 'bad' }))

        expect(replicator.bulk_upsert([orphan_token, tokens.first])).to contain_exactly(
          [orphan_token, :skipped, nil, nil],
          [tokens.first, :invalid_request, 'bad', 'REASON_INVALID']
        )
        expect(client).to have_received(:bulk_upsert_oauth_refresh_tokens)
          .once.with(tokens: [hash_including(source_id: tokens.first.id)])
      end

      it 'returns :skipped for every token without calling IAM when none can be sent', :aggregate_failures do
        expect(replicator.bulk_upsert([orphan_token])).to eq([[orphan_token, :skipped, nil, nil]])
        expect(client).not_to have_received(:bulk_upsert_oauth_refresh_tokens)
      end
    end

    context 'with no tokens' do
      it 'returns nothing without calling IAM', :aggregate_failures do
        expect(replicator.bulk_upsert([])).to eq([])
        expect(client).not_to have_received(:bulk_upsert_oauth_refresh_tokens)
      end
    end

    context 'when IAM returns a different number of results than tokens' do
      where(returned: [1, 3])

      with_them do
        before do
          allow(client).to receive(:bulk_upsert_oauth_refresh_tokens)
            .and_return(response(*Array.new(returned) { { reason: :REASON_WRITTEN } }))
        end

        it 'raises' do
          expect { replicator.bulk_upsert(tokens) }.to raise_error(
            ::Authn::IamService::GrpcClient::RequestError, "IAM returned #{returned} results for 2 tokens"
          )
        end
      end
    end

    context 'when IAM fails the whole call' do
      let(:error) { ::Authn::IamService::GrpcClient::RequestError.new('aborted', reason: :conflict) }

      before do
        allow(client).to receive(:bulk_upsert_oauth_refresh_tokens).and_raise(error)
      end

      it 'raises' do
        expect { replicator.bulk_upsert(tokens) }.to raise_error(error)
      end
    end
  end
end
