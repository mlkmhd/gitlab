# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'Revoke a cluster agent token', feature_category: :deployment_management do
  include GraphqlHelpers

  let_it_be(:project) { create(:project) }
  let_it_be(:current_user) { create(:user, maintainer_of: project) }
  let_it_be(:cluster_agent) { create(:cluster_agent, project: project) }

  let(:agent_token) { create(:cluster_agent_token, agent: cluster_agent) }
  let(:mutation) { graphql_mutation(:cluster_agent_token_revoke, { id: agent_token.to_global_id.to_s }, 'errors') }

  def mutation_response
    graphql_mutation_response(:cluster_agent_token_revoke)
  end

  it_behaves_like 'authorizing granular token permissions for GraphQL', :revoke_cluster_agent_token do
    let(:user) { current_user }
    let(:boundary_object) { project }
    let(:request) { post_graphql_mutation(mutation, token: { personal_access_token: pat }) }
  end

  context 'when a granular token can revoke the tokens of the project' do
    let(:pat) do
      create(:granular_pat, user: current_user, boundary: ::Authz::Boundary.for(project),
        permissions: %w[revoke_cluster_agent_token])
    end

    it 'revokes the token', :aggregate_failures do
      post_graphql_mutation(mutation, token: { personal_access_token: pat })

      expect(graphql_errors).to be_nil
      expect(mutation_response['errors']).to be_empty
      expect(agent_token.reload).to be_revoked
    end
  end

  context 'when a granular token can revoke the tokens of another project only' do
    let_it_be(:other_project) { create(:project, maintainers: current_user) }

    let(:pat) do
      create(:granular_pat, user: current_user, boundary: ::Authz::Boundary.for(other_project),
        permissions: %w[revoke_cluster_agent_token])
    end

    it 'does not revoke the token', :aggregate_failures do
      post_graphql_mutation(mutation, token: { personal_access_token: pat })

      expect(graphql_errors).to be_present
      expect(agent_token.reload).not_to be_revoked
    end
  end
end
