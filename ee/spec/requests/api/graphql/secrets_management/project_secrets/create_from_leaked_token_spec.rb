# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'Create project secret from a leaked token', :gitlab_secrets_manager, feature_category: :secrets_management do
  include GraphqlHelpers

  let_it_be(:group, freeze: false) { create(:group) }
  let_it_be_with_reload(:project) { create(:project, group: group) }
  let_it_be(:owner) { create(:user, owner_of: project) }
  let_it_be(:guest) { create(:user, guest_of: project) }
  let_it_be(:mutation_name) { :project_secret_create_from_leaked_token }

  let_it_be_with_refind(:secrets_manager) { create(:project_secrets_manager, project: project) }

  let(:current_user) { owner }
  let(:personal_access_token) { create(:personal_access_token, user: owner) }
  let(:finding) do
    create(:vulnerabilities_finding, :with_secret_detection_pat, project: project,
      token_value: personal_access_token.token)
  end

  let(:vulnerability) { finding.vulnerability.tap { |v| v.update!(report_type: :secret_detection) } }

  let(:params) do
    {
      vulnerability_id: vulnerability.to_global_id.to_s,
      name: 'ROTATED_SECRET',
      description: 'Rotated from a leaked token'
    }
  end

  let(:mutation) { graphql_mutation(mutation_name, params) }
  let(:mutation_response) { graphql_mutation_response(mutation_name) }

  subject(:post_mutation) { post_graphql_mutation(mutation, current_user: current_user) }

  before do
    stub_licensed_features(native_secrets_management: true, security_dashboard: true)
    stub_last_activity_update
    provision_project_secrets_manager(secrets_manager, owner)
  end

  after do
    cancel_exclusive_project_secret_operation_lease(project)
  end

  shared_examples 'a refused request that keeps the token' do
    it 'does not revoke the token' do
      post_mutation

      expect(personal_access_token.reload).not_to be_revoked
    end
  end

  context 'when the request is not authenticated' do
    let(:current_user) { nil }

    it_behaves_like 'a mutation on an unauthorized resource'
    it_behaves_like 'a refused request that keeps the token'
  end

  context 'when the current user is not a project member' do
    let(:current_user) { create(:user) }

    it_behaves_like 'a mutation on an unauthorized resource'
    it_behaves_like 'a refused request that keeps the token'
  end

  context 'when the current user is a guest' do
    let(:current_user) { guest }

    it_behaves_like 'a mutation on an unauthorized resource'
    it_behaves_like 'a refused request that keeps the token'
  end

  context 'when the vulnerability does not exist' do
    let(:params) do
      super().merge(vulnerability_id: ::Gitlab::GlobalId.build(model_name: 'Vulnerability',
        id: non_existing_record_id).to_s)
    end

    it_behaves_like 'a mutation on an unauthorized resource'
  end

  context 'when the vulnerability belongs to a project the user cannot access' do
    let(:other_finding) do
      create(:vulnerabilities_finding, :with_secret_detection_pat, project: create(:project),
        token_value: personal_access_token.token)
    end

    let(:params) { super().merge(vulnerability_id: other_finding.vulnerability.to_global_id.to_s) }

    it_behaves_like 'a mutation on an unauthorized resource'
    it_behaves_like 'a refused request that keeps the token'
  end

  context 'when the secrets_manager_pat_rotation feature flag is disabled' do
    before do
      stub_feature_flags(secrets_manager_pat_rotation: false)
    end

    it_behaves_like 'a mutation on an unauthorized resource'
    it_behaves_like 'a refused request that keeps the token'
  end

  context 'when the secrets_manager_pat_rotation feature flag is enabled only for the project' do
    before do
      stub_feature_flags(secrets_manager_pat_rotation: project)
    end

    it_behaves_like 'a mutation on an unauthorized resource'
    it_behaves_like 'a refused request that keeps the token'
  end

  context 'when the secrets_manager_pat_rotation feature flag is enabled for the top-level group' do
    before do
      stub_feature_flags(secrets_manager_pat_rotation: group)
    end

    it 'rotates the token' do
      post_mutation

      expect(mutation_response['errors']).to be_empty
      expect(personal_access_token.reload).to be_revoked
    end
  end

  context 'when Secrets Manager is not licensed' do
    before do
      stub_licensed_features(native_secrets_management: false, security_dashboard: true)
    end

    it_behaves_like 'a mutation on an unauthorized resource'
    it_behaves_like 'a refused request that keeps the token'
  end

  context 'when the Secrets Manager entitlement blocks writes' do
    it_behaves_like 'a secrets manager mutation blocked on entitlement' do
      let(:payload_key) { 'projectSecret' }
      let(:service_class) { SecretsManagement::ProjectSecrets::CreateFromLeakedTokenService }
    end

    context 'when the entitlement is read-only' do
      before do
        allow(SecretsManagement::Entitlement).to receive(:for)
          .and_return(SecretsManagement::Entitlement.new(state: :blocked, blocked_reason: :grace))
      end

      it 'returns the structured GRACE denial and keeps the token', :aggregate_failures do
        post_mutation

        expect(mutation_response['projectSecret']).to be_nil
        expect(mutation_response['errors'])
          .to include(SecretsManagement::EnforcesWriteEntitlement::WRITE_DENIAL_MESSAGE)
        expect(mutation_response['reason']).to eq('GRACE')
        expect(personal_access_token.reload).not_to be_revoked
      end

      # Reporters can see Secrets Manager status but not vulnerabilities, so the
      # denial reason must not tell them which vulnerability IDs exist.
      context 'when the user is a Reporter' do
        let_it_be(:reporter) { create(:user, reporter_of: project) }
        let(:current_user) { reporter }

        context 'with an existing vulnerability' do
          it_behaves_like 'a mutation on an unauthorized resource'
          it_behaves_like 'a refused request that keeps the token'
        end

        context 'with a nonexistent vulnerability' do
          let(:params) do
            {
              vulnerability_id: "gid://gitlab/Vulnerability/#{non_existing_record_id}",
              name: 'ROTATED_SECRET'
            }
          end

          it_behaves_like 'a mutation on an unauthorized resource'
        end
      end
    end
  end

  context 'when the vulnerability is not from secret detection' do
    let(:vulnerability) { create(:vulnerability, :with_finding, project: project, report_type: :sast) }

    it 'returns the error' do
      post_mutation

      expect(mutation_response['errors']).to contain_exactly('Not a secret detection vulnerability')
      expect(mutation_response['projectSecret']).to be_nil
    end
  end

  context 'when the leaked token is already revoked' do
    before do
      personal_access_token.revoke!
    end

    it 'returns an error and stores no secret' do
      post_mutation

      expect(mutation_response['errors']).to be_present
      expect(mutation_response['projectSecret']).to be_nil
    end
  end

  context 'when the secret name is invalid' do
    let(:params) { super().merge(name: 'invalid name!') }

    it_behaves_like 'a refused request that keeps the token'

    it 'returns the validation error' do
      post_mutation

      expect(mutation_response['errors'])
        .to include(a_string_including("Name can contain only letters, digits and '_'."))
    end
  end

  context 'when a secret with the same name already exists' do
    before do
      SecretsManagement::ProjectSecrets::CreateService.new(project, owner)
        .execute(name: 'ROTATED_SECRET', value: 'existing-value', environment: '*', branch: '*')
    end

    it_behaves_like 'a refused request that keeps the token'

    it 'returns the duplicate error' do
      post_mutation

      expect(mutation_response['errors']).to contain_exactly("A secret named 'ROTATED_SECRET' already exists")
    end
  end

  context 'when another secret operation holds the project lock' do
    include ExclusiveLeaseHelpers

    before do
      stub_exclusive_lease_taken("project_secret_operation:project_#{project.id}")
    end

    it 'returns the error' do
      post_mutation

      expect(mutation_response['errors']).to include(a_string_including('Another secret operation in progress'))
    end

    it_behaves_like 'a refused request that keeps the token'
  end

  context 'with a project-only fine-grained token' do
    let(:pat) do
      create(:granular_pat, user: owner, boundary: ::Authz::Boundary.for(project),
        permissions: ::Authz::PermissionGroups::Assignable.preferred_for_permission(:create_secret).name)
    end

    it 'is refused and does not revoke the token', :aggregate_failures do
      post_graphql_mutation(mutation, token: { personal_access_token: pat })

      expect(graphql_errors).to include(a_hash_including(
        'message' => a_string_including('with the following user permissions: [Personal Access Token: Rotate]')
      ))
      expect(personal_access_token.reload).not_to be_revoked
    end
  end

  context 'when the request succeeds' do
    before do
      (project.security_setting || project.create_security_setting).update!(validity_checks_enabled: true)
    end

    it 'rotates the token, stores the secret and marks the leaked token inactive', :aggregate_failures do
      post_mutation

      expect(mutation_response['errors']).to be_empty
      expect(graphql_data_at(mutation_name, :project_secret)).to match(a_graphql_entity_for(
        project: a_graphql_entity_for(project),
        name: 'ROTATED_SECRET',
        description: 'Rotated from a leaked token',
        environment: '*',
        branch: '*'
      ))
      expect(personal_access_token.reload).to be_revoked
      expect(SecretsManagement::ProjectSecrets::ReadMetadataService.new(project, owner).execute('ROTATED_SECRET'))
        .to be_success
      expect(finding.reload.finding_token_status&.status).to eq('inactive')
    end

    it_behaves_like 'internal event tracking' do
      let(:event) { 'create_ci_secret' }
      let(:user) { owner }
      let(:namespace) { project.namespace }
      let(:category) { 'Mutations::SecretsManagement::ProjectSecrets::CreateFromLeakedToken' }
    end

    it 'tracks the rotation outcome' do
      expect { post_mutation }.to trigger_internal_events('rotate_leaked_token_from_vulnerability')
        .with(user: owner, project: project, namespace: project.namespace,
          category: 'SecretsManagement::ProjectSecrets::CreateFromLeakedTokenService',
          additional_properties: { label: 'success', property: 'legacy' })
    end

    it 'never returns a token value' do
      post_mutation

      expect(response.body).not_to include(personal_access_token.token)
      expect(response.body).not_to include(::PersonalAccessToken.token_prefix)
    end
  end

  describe 'actor and token matrix' do
    using RSpec::Parameterized::TableSyntax

    let_it_be(:reporter) { create(:user, reporter_of: project) }
    let_it_be(:developer) { create(:user, developer_of: project) }
    let_it_be(:maintainer) { create(:user, maintainer_of: project) }
    let_it_be(:admin) { create(:admin) }
    let_it_be(:admin_owner) { create(:admin, owner_of: project) }
    let_it_be(:project_bot) { create(:user, :project_bot, maintainer_of: project) }

    # A PAT-authenticated GraphQL request runs an admin in admin mode, so admin mode itself is covered in the
    # CreateFromRotatedTokenService spec.
    let(:current_user) { public_send(actor) }
    let(:personal_access_token) { create(:personal_access_token, user: public_send(token_owner)) }

    context 'when the rotation succeeds' do
      where(:actor, :token_owner) do
        :developer   | :developer
        :maintainer  | :maintainer
        :admin_owner | :developer
        :admin_owner | :project_bot
      end

      with_them do
        it 'rotates the token and stores the secret', :aggregate_failures do
          post_mutation

          expect(mutation_response['errors']).to be_empty
          expect(personal_access_token.reload).to be_revoked
          expect(graphql_data_at(mutation_name, :project_secret, :name)).to eq('ROTATED_SECRET')
        end
      end
    end

    context 'when the actor cannot reach the vulnerability' do
      # Reading a vulnerability needs Developer, so a Reporter is refused even with a Secrets Manager grant.
      where(:actor, :token_owner) do
        :reporter | :reporter
      end

      with_them do
        before do
          update_project_secrets_permission(user: owner, project: project, actions: %w[read create],
            principal: { id: Gitlab::Access::REPORTER, type: 'Role' })
        end

        it_behaves_like 'a mutation on an unauthorized resource'
        it_behaves_like 'a refused request that keeps the token'
      end
    end

    context 'when the service refuses the rotation' do
      # A non-member admin has no Secrets Manager role, so OpenBao refuses the store before rotation.
      where(:actor, :token_owner, :error) do
        :owner | :developer   | 'You are not allowed to rotate this personal access token'
        :owner | :project_bot | 'You are not allowed to rotate this personal access token'
        :admin | :developer   | 'You are not allowed to create secrets in this project'
      end

      with_them do
        it 'returns the error and keeps the token', :aggregate_failures do
          post_mutation

          expect(mutation_response['errors']).to contain_exactly(error)
          expect(mutation_response['projectSecret']).to be_nil
          expect(personal_access_token.reload).not_to be_revoked
        end
      end
    end
  end

  describe 'leaked token kind and fine-grained token enforcement' do
    using RSpec::Parameterized::TableSyntax

    let(:personal_access_token) do
      if granular
        create(:granular_pat, user: owner, boundary: ::Authz::Boundary.for(project), permissions: :create_work_item)
      else
        create(:personal_access_token, user: owner)
      end
    end

    before do
      stub_feature_flags(granular_personal_access_tokens: owner)
      allow(Gitlab::CurrentSettings).to receive(:granular_tokens_enforced?).and_return(enforced)
    end

    where(:granular, :enforced, :error) do
      true  | false | nil
      true  | true  | nil
      false | true  | 'Rotation of legacy personal access tokens is disabled. Use a fine-grained token instead.'
    end

    with_them do
      it 'rotates the token unless enforcement refuses a legacy token', :aggregate_failures do
        post_mutation

        expect(mutation_response['errors']).to eq(Array(error))
        expect(personal_access_token.reload.revoked?).to eq(error.nil?)
      end
    end
  end

  it_behaves_like 'authorizing granular token permissions for GraphQL', :create_secret do
    let(:user) { owner }
    let(:boundary_object) { project }
    let(:request) { post_graphql_mutation(mutation, token: { personal_access_token: pat }) }

    before do
      next unless pat.granular?

      scope = create(:granular_scope, boundary: ::Authz::Boundary.for(:user),
        permissions: [:rotate_personal_access_token], organization: pat.organization)
      create(:personal_access_token_granular_scope, personal_access_token: pat, granular_scope: scope,
        organization: pat.organization)
    end
  end
end
