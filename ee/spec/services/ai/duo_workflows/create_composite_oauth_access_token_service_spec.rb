# frozen_string_literal: true

require 'spec_helper'

RSpec.describe ::Ai::DuoWorkflows::CreateCompositeOauthAccessTokenService, feature_category: :duo_agent_platform do
  describe '#execute' do
    let_it_be(:organization) { create(:organization) }
    let_it_be_with_reload(:service_account) { create(:user, :service_account, composite_identity_enforced: true) }
    let_it_be(:user) { create(:user, organizations: [organization]) }
    let_it_be_with_reload(:oauth_app) { create(:doorkeeper_application, scopes: %w[ai_workflows mcp user:*]) }

    subject(:response) do
      described_class.new(current_user: user, organization: organization, service_account: service_account).execute
    end

    before do
      stub_saas_features(duo_workflow: true)
      stub_feature_flags(duo_workflow_use_token_issuer: false)
    end

    context 'when service account and oauth app exists' do
      before do
        ::Ai::Setting.for_organization(organization).update!(duo_workflow_oauth_application_id: oauth_app.id)
      end

      context 'when oauth app has correct scopes' do
        it 'creates a new oauth access token that defaults to the one hour interactive lifetime' do
          expect(oauth_app).not_to receive(:update!)
          expect { response }.to change { OauthAccessToken.count }.by(1)
          expect(response).to be_success

          oauth_token = OauthAccessToken.last
          expect(oauth_token.scopes).to contain_exactly('mcp', 'ai_workflows', "user:#{user.id}")
          expect(oauth_token.expires_in).to eq(3600)
        end

        context 'when expires_in is provided below the instance-wide ceiling' do
          subject(:response) do
            described_class.new(
              current_user: user,
              organization: organization,
              service_account: service_account,
              expires_in: 90.minutes
            ).execute
          end

          it 'mints a token with the given lifetime' do
            expect(response).to be_success
            expect(response[:oauth_access_token].expires_in).to eq(90.minutes.to_i)
          end

          it 'records the given lifetime on the audit event' do
            expect(::Gitlab::Audit::Auditor).to receive(:audit).with(
              hash_including(additional_details: hash_including(expires_in: 90.minutes.to_i))
            )

            response
          end
        end

        context 'when expires_in exceeds the instance-wide ceiling' do
          subject(:response) do
            described_class.new(
              current_user: user,
              organization: organization,
              service_account: service_account,
              expires_in: 6.hours
            ).execute
          end

          it 'clamps the minted token lifetime to the ceiling' do
            expect(response).to be_success
            expect(response[:oauth_access_token].expires_in)
              .to eq(::Ai::DuoWorkflows::WorkloadCredential::EXPIRES_IN.to_i)
          end

          it 'clamps the audit event lifetime to the ceiling' do
            expect(::Gitlab::Audit::Auditor).to receive(:audit).with(
              hash_including(
                additional_details: hash_including(
                  expires_in: ::Ai::DuoWorkflows::WorkloadCredential::EXPIRES_IN.to_i
                )
              )
            )

            response
          end
        end

        it 'adds a scope naming the workflow when given a workflow ID' do
          token = described_class.new(
            current_user: user, organization: organization, service_account: service_account, workflow_id: 42
          ).execute[:oauth_access_token]

          expect(token.scopes).to contain_exactly('mcp', 'ai_workflows', "user:#{user.id}", 'duo_workflow:42')
        end

        it 'creates a composite_oauth_token_created audit event scoped to the service account' do
          expect(::Gitlab::Audit::Auditor).to receive(:audit).with(
            hash_including(
              name: 'composite_oauth_token_created',
              author: user,
              scope: service_account,
              target: service_account,
              message: 'Created composite OAuth token for Duo workflow',
              additional_details: hash_including(
                scopes: include('ai_workflows', 'mcp'),
                expires_in: 3600,
                token_type: 'oauth'
              )
            )
          )

          response
        end

        context 'when a container is provided' do
          let_it_be(:project) { create(:project) }

          subject(:response) do
            described_class.new(
              current_user: user,
              organization: organization,
              service_account: service_account,
              container: project
            ).execute
          end

          it 'creates a composite_oauth_token_created audit event scoped to the container' do
            expect(::Gitlab::Audit::Auditor).to receive(:audit).with(
              hash_including(
                name: 'composite_oauth_token_created',
                author: user,
                scope: project,
                target: service_account
              )
            )

            response
          end
        end
      end

      context 'when service account does not have composite identity enabled' do
        before do
          service_account.update!(composite_identity_enforced: false)
        end

        it 'raises CompositeIdentityEnforcedError' do
          expect { response }.to raise_error(
            ::Ai::DuoWorkflows::CreateCompositeOauthAccessTokenService::CompositeIdentityEnforcedError,
            "Service account does not exist or does not have composite identity enabled."
          )
        end
      end

      context 'when the oauth application is missing mcp scope' do
        before do
          oauth_app.update!(scopes: %w[ai_workflows user:*])
        end

        it 'updates the scopes to contain mcp scope' do
          expect { response }.to change { OauthAccessToken.count }.by(1)
          token = response[:oauth_access_token]
          expect(token.resource_owner_id).to eq service_account.id
          expect(token.application).to eq oauth_app
          expect(token.scopes).to include('mcp', 'ai_workflows')
          expect(oauth_app.reload.scopes).to include('mcp', 'ai_workflows')
        end
      end
    end

    context 'when duo_workflow_use_token_issuer is enabled' do
      let_it_be(:cloud_connector_key) { create(:cloud_connector_keys) }

      before do
        stub_feature_flags(duo_workflow_use_token_issuer: user)
        allow(::CloudConnector::CachingKeyLoader).to receive(:private_jwk).and_return(cloud_connector_key.to_jwk)
        allow(::CloudConnector::Keys).to receive(:valid).and_return([cloud_connector_key])
      end

      it 'returns success without creating an OAuth application or token' do
        expect { response }.to not_change { OauthAccessToken.count }.and not_change { Authn::OauthApplication.count }
        expect(response).to be_success
      end

      it 'returns a plaintext JWT prefixed as a StatelessAccessToken', :freeze_time do
        token = response[:oauth_access_token]

        expect(token.plaintext_token).to start_with(::Authn::Tokens::StatelessAccessToken::TOKEN_PREFIX)
        expect(token.expires_in).to eq(3600)
        expect(token.expires_at).to eq(3600.seconds.from_now)
      end

      context 'when expires_in exceeds the instance-wide ceiling' do
        subject(:response) do
          described_class.new(
            current_user: user,
            organization: organization,
            service_account: service_account,
            expires_in: 6.hours
          ).execute
        end

        it 'clamps the JWT lifetime to the ceiling', :freeze_time do
          ceiling = ::Ai::DuoWorkflows::WorkloadCredential::EXPIRES_IN

          expect(response[:oauth_access_token].expires_in).to eq(ceiling.to_i)
          expect(response[:oauth_access_token].expires_at).to eq(ceiling.from_now)
        end
      end

      it 'embeds the human user in the identities claim and the service account as sub' do
        decoded = ::Authn::Tokens::StatelessAccessToken.from_jwt(response[:oauth_access_token].plaintext_token)

        expect(decoded.user).to eq(service_account)
        expect(decoded.identity_user).to eq(user)
        expect(decoded.scopes.to_a).to contain_exactly('ai_workflows', 'mcp')
      end

      it 'adds a scope naming the workflow when given a workflow ID' do
        result = described_class.new(
          current_user: user, organization: organization, service_account: service_account, workflow_id: 42
        ).execute
        decoded = ::Authn::Tokens::StatelessAccessToken.from_jwt(result[:oauth_access_token].plaintext_token)

        expect(decoded.scopes.to_a).to contain_exactly('ai_workflows', 'mcp', 'duo_workflow:42')
      end

      it 'emits the composite_oauth_token_created audit event marked as a stateless JWT' do
        expect(::Gitlab::Audit::Auditor).to receive(:audit).with(
          hash_including(
            name: 'composite_oauth_token_created',
            author: user,
            additional_details: hash_including(token_type: 'stateless_jwt')
          )
        )

        response
      end

      context 'when no Cloud Connector signing key is configured' do
        before do
          allow(::CloudConnector::Keys).to receive(:valid).and_return([])
        end

        it 'falls back to a real OAuth token, with the dynamic user scope, instead of failing' do
          expect(response).to be_success

          token = response[:oauth_access_token]
          expect(token).to be_a(OauthAccessToken)
          expect(token.scopes.to_a).to include("user:#{user.id}")
        end
      end
    end

    context 'when the oauth application does not exist' do
      it 'creates an oauth application to generate the token' do
        expect { response }.to change { Authn::OauthApplication.count }.by(1).and change {
          OauthAccessToken.count
        }.by(1)
        expect(response).to be_success
      end

      context 'when oauth app creation is successful but AI settings fail to save' do
        before do
          allow_next_instance_of(::Ai::Setting) do |instance|
            allow(instance).to receive(:update!).and_raise(ActiveRecord::RecordInvalid)
          end
        end

        it 'rolls back the oauth application creation' do
          expect { response }.to not_change {
            Authn::OauthApplication.count
          }
        end

        it 'expects error response' do
          expect(response).to be_error
          expect(response.message).to eq('Failed to generate composite oauth token')
        end
      end
    end
  end

  describe '#ai_settings' do
    let_it_be(:organization) { create(:organization) }
    let(:setting) { build(:ai_settings) }
    let_it_be(:service_account) { create(:user, :service_account) }
    let_it_be(:user) { create(:user, organizations: [organization]) }

    subject(:service) do
      described_class.new(current_user: user, organization: organization, service_account: service_account)
    end

    it 'reads the settings for the organization' do
      expect(Ai::Setting).to receive(:for_organization).with(organization).and_return(setting)

      expect(service.send(:ai_settings)).to eq(setting)
    end
  end
end
