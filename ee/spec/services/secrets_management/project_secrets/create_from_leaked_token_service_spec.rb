# frozen_string_literal: true

require 'spec_helper'

RSpec.describe SecretsManagement::ProjectSecrets::CreateFromLeakedTokenService, :gitlab_secrets_manager,
  feature_category: :secrets_management do
  let_it_be_with_reload(:project) { create(:project) }
  let_it_be(:user) { create(:user) }

  let(:secrets_manager) { create(:project_secrets_manager, project: project) }
  let(:personal_access_token) { create(:personal_access_token, user: user) }
  let(:token_value) { personal_access_token.token }
  let(:finding) do
    create(:vulnerabilities_finding, :with_secret_detection_pat, project: project, token_value: token_value)
  end

  let(:report_type) { :secret_detection }
  let(:vulnerability) do
    finding.vulnerability.tap { |v| v.update!(report_type: report_type) }
  end

  let(:service) { described_class.new(project, user) }

  subject(:result) do
    service.execute(vulnerability_id: vulnerability.id, name: 'ROTATED_SECRET',
      environment: '*', branch: '*', description: 'Rotated from a leaked token')
  end

  before_all do
    project.add_owner(user)
  end

  before do
    stub_licensed_features(native_secrets_management: true, security_dashboard: true)
  end

  describe '#execute' do
    context 'when the user cannot read the vulnerability' do
      before do
        stub_licensed_features(native_secrets_management: true, security_dashboard: false)
      end

      it 'returns a vulnerability_not_found error and does not rotate the token', :aggregate_failures do
        expect(result).to be_error
        expect(result.reason).to eq(:vulnerability_not_found)
        expect(personal_access_token.reload).not_to be_revoked
      end
    end

    context 'when the vulnerability does not exist' do
      it 'returns a vulnerability_not_found error' do
        vulnerability # ensure the finding/vuln exist but pass a bad id
        expect(
          service.execute(vulnerability_id: non_existing_record_id, name: 'ROTATED_SECRET',
            environment: '*', branch: '*')
        ).to be_error.and(have_attributes(reason: :vulnerability_not_found))
      end
    end

    context 'when the vulnerability is not secret_detection' do
      let(:report_type) { :sast }

      it 'returns a not_secret_detection error' do
        expect(result).to be_error
        expect(result.reason).to eq(:not_secret_detection)
      end
    end

    context 'when the vulnerability has no finding' do
      let(:vulnerability) { create(:vulnerability, project: project, report_type: :secret_detection) }

      it 'returns a token_not_resolved error' do
        expect(result).to be_error
        expect(result.reason).to eq(:token_not_resolved)
      end
    end

    context 'when the finding has no token value' do
      let(:token_value) { nil }

      it 'returns a token_not_resolved error' do
        expect(result).to be_error
        expect(result.reason).to eq(:token_not_resolved)
      end
    end

    context 'when the leaked token cannot be resolved to a personal access token' do
      let(:token_value) { 'glpat-thisisnotarealtoken00' }

      it 'returns a token_not_resolved error' do
        expect(result).to be_error
        expect(result.reason).to eq(:token_not_resolved)
      end
    end

    context 'when the secrets manager is active and the token resolves' do
      before do
        provision_project_secrets_manager(secrets_manager, user)
      end

      it 'rotates the leaked token and stores the new value as a project secret' do
        expect(result).to be_success

        secret = result.payload[:secret]
        expect(secret.name).to eq('ROTATED_SECRET')
        expect(secret.environment).to eq('*')
        expect(personal_access_token.reload).to be_revoked
      end

      context 'when validity checks are enabled' do
        before do
          project.security_setting.update!(validity_checks_enabled: true)
        end

        it 'refreshes the token status of the finding' do
          expect_next_instance_of(Security::SecretDetection::UpdateTokenStatusService) do |status_service|
            expect(status_service).to receive(:execute_for_vulnerability_finding).with(finding.id)
          end

          expect(result).to be_success
        end

        context 'when refreshing the token status fails' do
          let(:status_error) { StandardError.new('status refresh failed') }

          before do
            allow_next_instance_of(Security::SecretDetection::UpdateTokenStatusService) do |status_service|
              allow(status_service).to receive(:execute_for_vulnerability_finding).and_raise(status_error)
            end
          end

          it 'still succeeds and tracks the exception', :aggregate_failures do
            expect(Gitlab::ErrorTracking).to receive(:track_exception)
              .with(status_error, vulnerability_finding_id: finding.id)

            expect(result).to be_success
            expect(personal_access_token.reload).to be_revoked
          end
        end
      end

      shared_examples 'skips the token status refresh and logs why' do
        it 'still succeeds, skips the refresh and logs why', :aggregate_failures do
          expect(Security::SecretDetection::UpdateTokenStatusService).not_to receive(:new)
          allow(Gitlab::AppLogger).to receive(:info)
          expect(Gitlab::AppLogger).to receive(:info).with(a_hash_including(
            Labkit::Fields::LOG_MESSAGE =>
              'Skipped token status refresh after rotating a leaked token: validity checks are disabled',
            Labkit::Fields::GL_PROJECT_ID => project.id,
            vulnerability_finding_id: finding.id
          ))

          expect(result).to be_success
          expect(personal_access_token.reload).to be_revoked
        end
      end

      context 'when validity checks are disabled' do
        before do
          project.security_setting.update!(validity_checks_enabled: false)
        end

        it_behaves_like 'skips the token status refresh and logs why'
      end

      context 'when the project has no security setting' do
        before do
          project.security_setting.destroy!
          project.reload
        end

        it_behaves_like 'skips the token status refresh and logs why'
      end

      context 'when the leaked token is fine-grained' do
        let(:personal_access_token) do
          create(:granular_pat, user: user, boundary: Authz::Boundary.for(project), permissions: :create_work_item)
        end

        it 'resolves and rotates it', :aggregate_failures do
          expect(result).to be_success
          expect(personal_access_token.reload).to be_revoked
          expect(user.personal_access_tokens.find_by(previous_personal_access_token_id: personal_access_token.id))
            .to be_granular
        end
      end
    end

    describe 'internal event tracking' do
      let(:event) { 'rotate_leaked_token_from_vulnerability' }
      let(:identifiers) { { user: user, project: project, namespace: project.namespace } }

      context 'when the rotation succeeds' do
        before do
          provision_project_secrets_manager(secrets_manager, user)
        end

        it 'tracks a success with the token type' do
          expect { result }.to trigger_internal_events(event)
            .with(**identifiers, additional_properties: { label: 'success', property: 'legacy' })
        end

        context 'when the leaked token is fine-grained' do
          let(:personal_access_token) do
            create(:granular_pat, user: user, boundary: Authz::Boundary.for(project), permissions: :create_work_item)
          end

          it 'tracks the granular token type' do
            expect { result }.to trigger_internal_events(event)
              .with(**identifiers, additional_properties: { label: 'success', property: 'granular' })
          end
        end
      end

      context 'when the token cannot be resolved' do
        let(:token_value) { nil }

        it 'tracks the reason without a token type' do
          expect { result }.to trigger_internal_events(event)
            .with(**identifiers, additional_properties: { label: 'token_not_resolved' })
        end
      end

      context 'when the leaked token is already revoked' do
        before do
          personal_access_token.revoke!
        end

        it 'tracks the revoked reason with the token type' do
          expect { result }.to trigger_internal_events(event)
            .with(**identifiers, additional_properties: { label: 'token_revoked', property: 'legacy' })
        end
      end

      context 'when the secrets manager is not active' do
        it 'tracks the inactive reason' do
          expect { result }.to trigger_internal_events(event)
            .with(**identifiers, additional_properties: { label: 'secrets_manager_inactive', property: 'legacy' })
        end
      end

      context 'when the rotation fails without a reason' do
        before do
          allow_next_instance_of(SecretsManagement::ProjectSecrets::CreateFromRotatedTokenService) do |service|
            allow(service).to receive(:execute).and_return(ServiceResponse.error(message: 'failed'))
          end
        end

        it 'tracks a generic error' do
          expect { result }.to trigger_internal_events(event)
            .with(**identifiers, additional_properties: { label: 'error', property: 'legacy' })
        end
      end

      context 'when the rotation raises' do
        before do
          allow_next_instance_of(SecretsManagement::ProjectSecrets::CreateFromRotatedTokenService) do |service|
            allow(service).to receive(:execute).and_raise(SecretsManagement::SecretsManagerClient::ConnectionError)
          end
        end

        it 'tracks the exception and re-raises' do
          expect { expect { result }.to raise_error(SecretsManagement::SecretsManagerClient::ConnectionError) }
            .to trigger_internal_events(event)
            .with(**identifiers, additional_properties: { label: 'exception', property: 'legacy' })
        end
      end
    end

    context 'when the secrets manager is not active' do
      it 'does not refresh the token status' do
        expect(Security::SecretDetection::UpdateTokenStatusService).not_to receive(:new)

        expect(result).to be_error
      end
    end
  end
end
