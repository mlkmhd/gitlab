# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'Project.cluster_agents.url_configurations', feature_category: :deployment_management do
  include GraphqlHelpers

  let_it_be(:project) { create(:project, :public) }
  let_it_be(:current_user) { create(:user, developer_of: project) }
  let_it_be(:url_configuration) do
    create(:cluster_agent_url_configuration, agent: create(:cluster_agent, project: project))
  end

  let(:query) do
    graphql_query_for(:project, { full_path: project.full_path },
      query_nodes(:cluster_agents, query_nodes(:url_configurations, :url)))
  end

  let(:agent_path) { [:project, :cluster_agents, :nodes, 0] }

  it_behaves_like 'denying a granular token that only authorizes the parent of a field',
    [:read_project, :read_cluster_agent] do
    let(:user) { current_user }
    let(:boundary_object) { project }
    let(:request) { post_graphql(query, token: { personal_access_token: pat }) }
    let(:parent_data_path) { agent_path }
    let(:field_data_path) { [*agent_path, :url_configurations] }
  end

  context 'when a granular token can read the URL configurations of the project' do
    let(:pat) do
      create(:granular_pat, user: current_user, boundary: ::Authz::Boundary.for(project),
        permissions: %w[read_project read_cluster_agent read_cluster_agent_url_configuration])
    end

    it 'returns the URL configuration', :aggregate_failures do
      post_graphql(query, token: { personal_access_token: pat })

      expect(graphql_errors).to be_nil
      expect(graphql_data_at(*agent_path, :url_configurations, :nodes, 0, :url)).to eq(url_configuration.url)
    end
  end
end
