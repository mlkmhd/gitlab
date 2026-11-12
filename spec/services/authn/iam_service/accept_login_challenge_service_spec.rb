# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Authn::IamService::AcceptLoginChallengeService, feature_category: :system_access do
  let_it_be(:user) { create(:user) }

  let(:iam_service_url) { 'https://iam.example.com' }
  let(:challenge) { 'a' * 64 }
  let(:redirect_url) { "#{iam_service_url}/oauth2/authorize?client_id=test-app&login_verifier=#{'b' * 64}" }

  let(:grpc_client) { instance_double(Authn::IamService::GrpcClient) }
  let(:service) { described_class.new(challenge: challenge, user: user, client: grpc_client) }

  subject(:result) { service.execute }

  before do
    allow(Authn::IamAuthService).to receive(:url).and_return(iam_service_url)
  end

  describe '#execute' do
    let(:response) { ::Gitlab::Iam::Auth::V1::LoginServiceAcceptResponse.new(redirect_to: redirect_url) }

    before do
      allow(grpc_client).to receive(:accept_login_challenge).and_return(response)
    end

    context 'when the IAM service accepts the challenge' do
      it 'returns a success response with the redirect URL', :aggregate_failures do
        expect(result).to be_success
        expect(result.payload[:redirect_to]).to eq(redirect_url)
      end

      it 'sends the correct gRPC request' do
        result

        expect(grpc_client).to have_received(:accept_login_challenge).with(
          challenge: challenge,
          subject: user.id.to_s,
          cell_id: Gitlab.config.cell.id.to_i,
          auth_time: nil,
          consent_facts: nil
        )
      end

      context 'when the user has a sign-in time' do
        let(:signed_in_at) { Time.zone.parse('2026-01-02 03:04:05.123456 UTC') }
        let(:user) { build_stubbed(:user, current_sign_in_at: signed_in_at) }

        it 'reports it as auth_time' do
          result

          expect(grpc_client).to have_received(:accept_login_challenge).with(
            hash_including(auth_time: Google::Protobuf::Timestamp.new(seconds: signed_in_at.to_i, nanos: 123_456_000))
          )
        end
      end
    end

    context 'with a client_id from the login redirect' do
      let_it_be(:application) { create(:oauth_application) }

      let(:client_id) { application.uid }
      let(:service) { described_class.new(challenge: challenge, user: user, client_id: client_id, client: grpc_client) }

      def sent_consent_facts
        result
        consent_facts = nil
        expect(grpc_client).to have_received(:accept_login_challenge) do |**kwargs|
          consent_facts = kwargs[:consent_facts]
        end
        consent_facts
      end

      it 'sends the consent facts for the application' do
        expect(sent_consent_facts).to eq(
          client_id: client_id, granular_application: false, active_consent_grant: false
        )
      end

      context 'when the application is granular' do
        let_it_be(:application) { create(:oauth_application, :granular) }

        it 'reports no active grant' do
          expect(sent_consent_facts).to eq(
            client_id: client_id, granular_application: true, active_consent_grant: false
          )
        end

        context 'when the user holds an active grant' do
          before_all do
            create(:oauth_consent_grant, user: user, application: application)
          end

          it 'reports the grant' do
            expect(sent_consent_facts).to include(active_consent_grant: true)
          end
        end

        context 'when the user holds a revoked grant' do
          before_all do
            create(:oauth_consent_grant, :revoked, user: user, application: application)
          end

          it 'reports no active grant' do
            expect(sent_consent_facts).to include(active_consent_grant: false)
          end
        end

        context 'when the granular_oauth_tokens flag is disabled' do
          before do
            stub_feature_flags(granular_oauth_tokens: false)
          end

          it 'does not report the application as granular' do
            expect(sent_consent_facts).to include(granular_application: false)
          end
        end
      end

      context 'when the application does not exist' do
        let(:client_id) { 'unknown-client' }

        it 'sends no consent facts' do
          expect(sent_consent_facts).to be_nil
        end
      end
    end

    context 'when the IAM service asks for a new sign-in' do
      let(:response) { ::Gitlab::Iam::Auth::V1::LoginServiceAcceptResponse.new(reauthenticate: true) }

      it 'returns a success response that asks for reauthentication', :aggregate_failures do
        expect(result).to be_success
        expect(result.payload).to eq(reauthenticate: true)
      end

      context 'when the user has a sign-in time' do
        let(:user) { build_stubbed(:user, current_sign_in_at: Time.zone.parse('2026-01-02 03:04:05.123456 UTC')) }

        it 'logs it with the reported auth_time' do
          allow(Gitlab::AuthLogger).to receive(:info)

          result

          expect(Gitlab::AuthLogger).to have_received(:info).with(
            message: 'IAM login challenge asks for a new sign-in',
            auth_time: '2026-01-02T03:04:05.123456Z',
            Labkit::Fields::GL_USER_ID => user.id
          )
        end
      end

      context 'when the response also has a redirect URL' do
        let(:response) do
          ::Gitlab::Iam::Auth::V1::LoginServiceAcceptResponse.new(reauthenticate: true, redirect_to: redirect_url)
        end

        it 'asks for reauthentication' do
          expect(result.payload).to eq(reauthenticate: true)
        end
      end
    end

    context 'when the gRPC client raises a RequestError' do
      before do
        allow(grpc_client).to receive(:accept_login_challenge)
          .and_raise(Authn::IamService::GrpcClient::RequestError, 'Failed to connect to IAM service')
      end

      include_examples 'iam service error response with user',
        reason: :service_unavailable,
        message: 'Failed to connect to IAM service'
    end

    context 'when the response is missing redirect_to' do
      let(:response) { ::Gitlab::Iam::Auth::V1::LoginServiceAcceptResponse.new(redirect_to: '') }

      include_examples 'iam service error response with user',
        reason: :invalid_response,
        message: 'IAM login accept response missing redirect_to'
    end

    context 'when redirect_to points to a different host' do
      let(:response) { ::Gitlab::Iam::Auth::V1::LoginServiceAcceptResponse.new(redirect_to: 'https://untrusted.com/oauth2/authorize') }

      include_examples 'iam service error response with user',
        reason: :invalid_redirect_url,
        message: 'IAM login accept response contains invalid redirect URL'
    end
  end
end
