# frozen_string_literal: true

require 'spec_helper'

RSpec.describe SecretsManagement::ProjectSecrets::CreateFromRotatedTokenService, :gitlab_secrets_manager,
  feature_category: :secrets_management do
  let_it_be_with_reload(:project) { create(:project) }
  let_it_be(:user) { create(:user) }

  let(:secrets_manager) { create(:project_secrets_manager, project: project) }
  let(:service) { described_class.new(project, user) }

  let(:personal_access_token) { create(:personal_access_token, user: user) }
  let(:name) { 'ROTATED_SECRET' }
  let(:environment) { 'production' }
  let(:branch) { 'main' }
  let(:description) { 'Rotated from a leaked token' }

  let(:params) do
    {
      personal_access_token_id: personal_access_token.id,
      name: name,
      environment: environment,
      branch: branch,
      description: description
    }
  end

  subject(:result) { service.execute(**params) }

  before_all do
    project.add_owner(user)
  end

  describe '#execute' do
    context 'when the secrets_manager_pat_rotation feature flag is disabled' do
      before do
        stub_feature_flags(secrets_manager_pat_rotation: false)
      end

      it 'returns a feature_disabled error and does not rotate the token' do
        expect(result).to be_error
        expect(result.reason).to eq(:feature_disabled)
        expect(personal_access_token.reload).not_to be_revoked
      end
    end

    context 'when the feature flag is enabled only for another top-level namespace' do
      before do
        stub_feature_flags(secrets_manager_pat_rotation: create(:group))
      end

      it 'returns a feature_disabled error' do
        expect(result.reason).to eq(:feature_disabled)
      end
    end

    context "when the feature flag is enabled for the project's top-level namespace" do
      before do
        stub_feature_flags(secrets_manager_pat_rotation: project.root_ancestor)
      end

      # No secrets manager exists here, so reaching that check proves the flag check passed.
      it 'passes the feature flag check and stops at the secrets manager check' do
        expect(result.message).to eq('Secrets manager is not active')
        expect(personal_access_token.reload).not_to be_revoked
      end
    end

    context 'when the project is in a subgroup' do
      let_it_be(:top_level_group) { create(:group) }
      let_it_be(:subgroup) { create(:group, parent: top_level_group) }
      let_it_be_with_reload(:project) { create(:project, group: subgroup) }

      before_all do
        project.add_owner(user)
      end

      context 'when the feature flag is enabled for the top-level group' do
        before do
          stub_feature_flags(secrets_manager_pat_rotation: top_level_group)
        end

        it 'passes the feature flag check' do
          expect(result.message).to eq('Secrets manager is not active')
        end
      end

      context 'when the feature flag is enabled only for the subgroup' do
        before do
          stub_feature_flags(secrets_manager_pat_rotation: subgroup)
        end

        it 'returns a feature_disabled error' do
          expect(result.reason).to eq(:feature_disabled)
        end
      end
    end

    context 'when the personal access token does not exist' do
      let(:params) { super().merge(personal_access_token_id: non_existing_record_id) }

      it 'returns a token_not_found error' do
        expect(result).to be_error
        expect(result.reason).to eq(:token_not_found)
      end
    end

    context 'when the user may not rotate the token' do
      let_it_be(:personal_access_token) { create(:personal_access_token, user: create(:user)) }

      it 'returns a forbidden error and does not rotate the token' do
        expect(result).to be_error
        expect(result.reason).to eq(:forbidden)
        expect(personal_access_token.reload).not_to be_revoked
      end
    end

    context 'when the personal access token is already revoked' do
      let(:personal_access_token) { create(:personal_access_token, :revoked, user: user) }

      it 'returns a token_revoked error and creates no new token' do
        expect(result).to be_error
        expect(result.reason).to eq(:token_revoked)
        expect(result.message).to eq('Token already revoked')
        expect(user.personal_access_tokens.count).to eq(1)
      end
    end

    context 'when the personal access token has expired' do
      let(:personal_access_token) { create(:personal_access_token, :expired, user: user) }

      it 'returns a token_expired error and does not rotate the token' do
        expect(result).to be_error
        expect(result.reason).to eq(:token_expired)
        expect(personal_access_token.reload).not_to be_revoked
        expect(user.personal_access_tokens.count).to eq(1)
      end
    end

    context 'when the secrets manager is not active' do
      before do
        secrets_manager
      end

      it 'returns an inactive error and does not rotate the token' do
        expect(result).to be_error
        expect(result.message).to eq('Secrets manager is not active')
        expect(personal_access_token.reload).not_to be_revoked
      end
    end

    context 'when the secrets manager is active' do
      before do
        provision_project_secrets_manager(secrets_manager, user)
      end

      it 'rotates the token and stores the new value as a project secret' do
        expect(result).to be_success

        secret = result.payload[:secret]
        expect(secret.name).to eq(name)
        expect(secret.environment).to eq(environment)
        expect(secret.branch).to eq(branch)

        expect(personal_access_token.reload).to be_revoked
      end

      it 'preserves the original token lifetime on the rotated token' do
        expect(result).to be_success

        new_token = user.personal_access_tokens.find_by(previous_personal_access_token_id: personal_access_token.id)
        expect(new_token).to be_present
        expect(new_token.expires_at).to eq(personal_access_token.expires_at)
      end

      context 'when the token is fine-grained' do
        let(:personal_access_token) do
          create(:granular_pat, user: user, boundary: Authz::Boundary.for(project), permissions: :create_work_item)
        end

        let(:new_token) do
          user.personal_access_tokens.find_by(previous_personal_access_token_id: personal_access_token.id)
        end

        def scope_attributes(token)
          token.granular_scopes.map { |scope| [scope.access, scope.namespace_id, scope.permissions.sort] }
        end

        it 'rotates the token with the same fine-grained permissions and stores it', :aggregate_failures do
          expect(result).to be_success
          expect(result.payload[:secret].name).to eq(name)
          expect(personal_access_token.reload).to be_revoked
          expect(new_token).to be_granular
          expect(scope_attributes(new_token)).to match_array(scope_attributes(personal_access_token))
        end
      end

      context 'when fine-grained tokens are enforced' do
        before do
          stub_feature_flags(granular_personal_access_tokens: user)
          allow(Gitlab::CurrentSettings).to receive(:granular_tokens_enforced?).and_return(true)
        end

        it 'refuses to rotate a legacy token and leaves it active', :aggregate_failures do
          expect(SecretsManagement::ProjectSecrets::CreateService).not_to receive(:new)

          expect(result).to be_error
          expect(result.message).to eq(
            'Rotation of legacy personal access tokens is disabled. Use a fine-grained token instead.'
          )
          expect(personal_access_token.reload).not_to be_revoked
        end

        context 'when the token is fine-grained' do
          let(:personal_access_token) do
            create(:granular_pat, user: user, boundary: Authz::Boundary.for(project), permissions: :create_work_item)
          end

          it 'rotates the token and stores the new value', :aggregate_failures do
            expect(result).to be_success
            expect(personal_access_token.reload).to be_revoked
          end
        end
      end

      describe "rotating another user's token" do
        using RSpec::Parameterized::TableSyntax

        let_it_be(:admin) { create(:admin, owner_of: project) }
        let_it_be(:developer) { create(:user, developer_of: project) }
        let_it_be(:project_bot) { create(:user, :project_bot, maintainer_of: project) }

        let(:service) { described_class.new(project, public_send(actor)) }
        let(:personal_access_token) { create(:personal_access_token, user: public_send(token_owner)) }

        context 'when admin mode is enabled', :enable_admin_mode do
          where(:actor, :token_owner) do
            :admin | :developer
            :admin | :project_bot
          end

          with_them do
            it 'rotates the token and stores the new value', :aggregate_failures do
              expect(result).to be_success
              expect(personal_access_token.reload).to be_revoked
            end
          end
        end

        context 'when admin mode is disabled' do
          # An owner can't rotate a project access token's bot either; remediation for bots is undecided.
          where(:actor, :token_owner) do
            :admin | :developer
            :user  | :developer
            :user  | :project_bot
          end

          with_them do
            it 'returns a forbidden error and does not rotate the token', :aggregate_failures do
              expect(result.reason).to eq(:forbidden)
              expect(personal_access_token.reload).not_to be_revoked
            end
          end
        end
      end

      context 'when the user can read secrets but not create them' do
        let_it_be(:reporter) { create(:user, reporter_of: project) }

        let(:service) { described_class.new(project, reporter) }
        let(:personal_access_token) { create(:personal_access_token, user: reporter) }

        before do
          update_project_secrets_permission(
            user: user, project: project, actions: %w[read], principal: { id: reporter.id, type: 'User' }
          )
        end

        it 'returns a create_forbidden error and does not rotate the token', :aggregate_failures do
          expect(PersonalAccessTokens::RotateService).not_to receive(:new)

          expect(result).to be_error
          expect(result.reason).to eq(:create_forbidden)
          expect(personal_access_token.reload).not_to be_revoked
        end
      end

      context 'when the user can create secrets but not read their metadata' do
        let_it_be(:creator) { create(:user, reporter_of: project) }

        let(:service) { described_class.new(project, creator) }
        let(:personal_access_token) { create(:personal_access_token, user: creator) }

        before do
          update_project_secrets_permission(
            user: user, project: project, actions: %w[create read_value], principal: { id: creator.id, type: 'User' }
          )
        end

        it 'rotates the token and stores the new value', :aggregate_failures do
          expect(result).to be_success
          expect(personal_access_token.reload).to be_revoked
        end
      end

      context 'when the namespace is not entitled to write secrets' do
        before do
          stub_secrets_manager_entitlement(state: :blocked, blocked_reason: :trial_expired)
        end

        it 'returns an entitlement_blocked error and does not rotate the token', :aggregate_failures do
          expect(result).to be_error
          expect(result.reason).to eq(:entitlement_blocked)
          expect(personal_access_token.reload).not_to be_revoked
        end
      end

      context 'when the project is archived' do
        before do
          project.update!(archived: true)
        end

        it 'returns a namespace_inactive error and does not rotate the token', :aggregate_failures do
          expect(result).to be_error
          expect(result.reason).to eq(:namespace_inactive)
          expect(personal_access_token.reload).not_to be_revoked
        end
      end

      context 'when a secret with the same name already exists' do
        before do
          SecretsManagement::ProjectSecrets::CreateService.new(project, user).execute(
            name: name,
            value: 'existing-value',
            environment: environment,
            branch: branch
          )
        end

        it 'returns a secret_exists error and does not rotate the token' do
          expect(result).to be_error
          expect(result.reason).to eq(:secret_exists)
          expect(personal_access_token.reload).not_to be_revoked
        end
      end

      context 'when the project has reached its secrets limit' do
        before do
          allow_next_instance_of(SecretsManagement::ProjectSecretsCountService) do |count_service|
            allow(count_service).to receive(:secrets_limit_exceeded?).and_return(true)
          end
        end

        it 'returns a secrets_limit_exceeded error and does not rotate the token', :aggregate_failures do
          expect(result).to be_error
          expect(result.reason).to eq(:secrets_limit_exceeded)
          expect(personal_access_token.reload).not_to be_revoked
        end
      end

      context 'when the secret name is invalid' do
        let(:name) { 'invalid name!' }

        it 'returns a validation error and does not rotate the token' do
          expect(result).to be_error
          expect(result.message).to include("Name can contain only letters, digits and '_'.")
          expect(personal_access_token.reload).not_to be_revoked
        end
      end

      context 'when the description is over the OpenBao custom metadata value limit' do
        # 200 characters, the frontend limit, but 600 bytes
        let(:description) { '密' * 200 }

        it 'returns a validation error and does not rotate the token' do
          expect(result).to be_error
          expect(result.message).to include('Description is too long (600 B). The maximum size is 512 B.')
          expect(personal_access_token.reload).not_to be_revoked
        end
      end

      context 'when the token is already revoked' do
        before do
          personal_access_token.revoke!
        end

        it 'returns the rotation error and does not attempt to store a secret' do
          expect(SecretsManagement::ProjectSecrets::CreateService).not_to receive(:new)

          expect(result).to be_error
          expect(result.message).to eq('Token already revoked')
        end
      end

      it_behaves_like 'an operation requiring an exclusive project secret operation lease'

      context 'when another secret operation holds the project lock' do
        include ExclusiveLeaseHelpers

        before do
          stub_exclusive_lease_taken("project_secret_operation:project_#{project.id}")
        end

        it 'refuses before rotating and keeps the token', :aggregate_failures do
          expect(result).to be_error
          expect(result.message).to include('Another secret operation in progress')
          expect(personal_access_token.reload).not_to be_revoked
          expect(user.personal_access_tokens.where(previous_personal_access_token_id: personal_access_token.id))
            .to be_empty
        end
      end

      context 'when storing the rotated value fails' do
        let(:new_token) do
          user.personal_access_tokens.find_by(previous_personal_access_token_id: personal_access_token.id)
        end

        let(:stored_values) { [] }

        before do
          allow_next_instance_of(SecretsManagement::ProjectSecrets::CreateService) do |create_service|
            allow(create_service).to receive(:execute_without_lease) do |value:, **|
              stored_values << value
              ServiceResponse.error(message: 'store failed')
            end
          end
        end

        it 'revokes the new token and returns a store_failed error', :aggregate_failures do
          expect(result).to be_error
          expect(result.reason).to eq(:store_failed)
          expect(result.message).to include('so it was revoked', 'store failed')
          expect(personal_access_token.reload).to be_revoked
          expect(new_token).to be_revoked
        end

        it 'logs the failure without the token value', :aggregate_failures do
          logs = []
          allow(Gitlab::AppJsonLogger).to receive(:warn) { |payload| logs << payload }

          result

          logged = logs.find { |payload| payload[:message].to_s.start_with?('Rotated personal access token') }
          expect(logged).to include(
            Labkit::Fields::GL_PROJECT_ID => project.id,
            personal_access_token_id: new_token.id,
            revoked: true
          )
          # A reloaded token has no cleartext, so check against the value the service tried to store.
          rotated_value = stored_values.sole
          expect(rotated_value).to start_with(::PersonalAccessToken.token_prefix)
          expect(logged.to_s).not_to include(rotated_value, personal_access_token.token)
        end

        context 'when the new token cannot be revoked' do
          before do
            allow_next_instance_of(PersonalAccessTokens::RevokeService) do |revoke_service|
              allow(revoke_service).to receive(:execute).and_return(ServiceResponse.error(message: 'revoke failed'))
            end
          end

          it 'tells the user to revoke it manually and tracks the failure', :aggregate_failures do
            expect(Gitlab::ErrorTracking).to receive(:track_exception)
              .with(an_instance_of(StandardError), hash_including(:personal_access_token_id, project_id: project.id))

            expect(result.reason).to eq(:store_failed)
            expect(result.message).to include('could not be stored or revoked', new_token.name)
          end

          it 'logs that the new token is still active' do
            allow(Gitlab::ErrorTracking).to receive(:track_exception)
            allow(Gitlab::AppJsonLogger).to receive(:warn)

            result

            expect(Gitlab::AppJsonLogger).to have_received(:warn).with(hash_including(revoked: false))
          end
        end
      end

      context 'when storing the rotated value raises' do
        let(:stored_values) { [] }

        before do
          allow_next_instance_of(SecretsManagement::ProjectSecrets::CreateService) do |create_service|
            allow(create_service).to receive(:execute_without_lease) do |value:, **|
              stored_values << value
              raise SecretsManagement::SecretsManagerClient::ConnectionError, 'connection refused'
            end
          end
        end

        it 'revokes the new token and re-raises', :aggregate_failures do
          expect { result }.to raise_error(SecretsManagement::SecretsManagerClient::ConnectionError)

          new_token = user.personal_access_tokens.find_by(previous_personal_access_token_id: personal_access_token.id)
          expect(new_token).to be_revoked
        end

        it 'logs the failure without the exception message or a token value', :aggregate_failures do
          logs = []
          allow(Gitlab::AppJsonLogger).to receive(:warn) { |payload| logs << payload }

          expect { result }.to raise_error(SecretsManagement::SecretsManagerClient::ConnectionError)

          logged = logs.find { |payload| payload[:message].to_s.start_with?('Rotated personal access token') }
          expect(logged).to include(revoked: true, store_error_reason: :exception)
          expect(logged.to_s).not_to include('connection refused', stored_values.sole, personal_access_token.token)
        end

        context 'when revoking the new token also raises' do
          before do
            allow_next_instance_of(PersonalAccessTokens::RevokeService) do |revoke_service|
              allow(revoke_service).to receive(:execute).and_raise(ActiveRecord::StatementInvalid, 'revoke failed')
            end
          end

          it 'still logs the failure and re-raises the store error', :aggregate_failures do
            logs = []
            allow(Gitlab::AppJsonLogger).to receive(:warn) { |payload| logs << payload }
            expect(Gitlab::ErrorTracking).to receive(:track_exception)
              .with(an_instance_of(ActiveRecord::StatementInvalid), hash_including(project_id: project.id))

            expect { result }.to raise_error(SecretsManagement::SecretsManagerClient::ConnectionError)

            logged = logs.find { |payload| payload[:message].to_s.start_with?('Rotated personal access token') }
            expect(logged).to include(revoked: nil, store_error_reason: :exception)
          end
        end
      end
    end
  end
end
