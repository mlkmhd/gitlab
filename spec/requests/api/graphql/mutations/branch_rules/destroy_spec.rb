# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'Deleting a BranchRule', feature_category: :source_code_management do
  include GraphqlHelpers

  let_it_be(:current_user) { create(:user) }
  let_it_be(:protected_branch) { create(:protected_branch) }
  let_it_be(:project) { protected_branch.project }

  let(:branch_rule) { Projects::BranchRule.new(project, protected_branch) }
  let(:global_id) { branch_rule.to_global_id.to_s }
  let(:mutation) { graphql_mutation(:branch_rule_delete, { id: global_id }) }
  let(:mutation_response) { graphql_mutation_response(:branch_rule_delete) }

  subject(:mutation_request) { post_graphql_mutation(mutation, current_user: current_user) }

  it_behaves_like 'authorizing granular token permissions for GraphQL', :delete_branch_rule do
    let(:user) { create(:user, maintainer_of: project) }
    let(:boundary_object) { project }
    let(:request) do
      post_graphql_mutation(
        graphql_mutation(:branch_rule_delete, { id: branch_rule.to_global_id.to_s }, 'errors'),
        token: { personal_access_token: pat })
    end
  end

  context 'when the user does not have permission' do
    it_behaves_like 'a mutation that returns top-level errors',
      errors: [Gitlab::Graphql::Authorize::AuthorizeResource::RESOURCE_ACCESS_ERROR]

    it 'does not destroy the BranchRule' do
      expect { mutation_request }.not_to change { ProtectedBranch.count }
    end
  end

  context 'when the user has permission' do
    before_all do
      project.add_maintainer(current_user)
    end

    it 'destroys the BranchRule' do
      expect { mutation_request }.to change { ProtectedBranch.count }.by(-1)
    end

    it 'returns an empty BranchRule' do
      mutation_request

      expect(mutation_response).to have_key('branchRule')
      expect(mutation_response['branchRule']).to be_nil
    end

    # BranchRules::DestroyService reports failures as a ServiceResponse, so the raised rate
    # limit error only reaches the client through GraphqlController's error map.
    context 'when the protected branch write limit is used up', :clean_gitlab_redis_rate_limiting do
      before do
        stub_application_setting(protected_branch_write_limit: 1)

        Gitlab::ApplicationRateLimiter.throttled?(
          :protected_branch_write, scope: { user: current_user, namespace: project.root_ancestor }
        )
      end

      it 'responds with 429 and keeps the BranchRule', :aggregate_failures do
        expect { mutation_request }.not_to change { ProtectedBranch.count }

        expect(response).to have_gitlab_http_status(:too_many_requests)
      end
    end

    context 'when an invalid global id is given' do
      let(:global_id) { project.to_gid.to_s }
      let(:error_message) { %("#{global_id}" does not represent an instance of Projects::BranchRule) }
      let(:global_id_error) { a_hash_including('message' => a_string_including(error_message)) }

      it 'returns an error' do
        mutation_request

        expect(graphql_errors).to include(global_id_error)
      end

      it 'does not destroy the BranchRule' do
        expect { mutation_request }.not_to change { ProtectedBranch.count }
      end
    end

    context 'when a branch rule is missing' do
      let(:protected_branch) { build(:protected_branch, id: non_existing_record_id) }

      it_behaves_like 'a mutation that returns top-level errors',
        errors: [Gitlab::Graphql::Authorize::AuthorizeResource::RESOURCE_ACCESS_ERROR]

      it 'does not destroy the BranchRule' do
        expect { mutation_request }.not_to change { ProtectedBranch.count }
      end
    end
  end
end
