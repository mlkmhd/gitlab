# frozen_string_literal: true

require 'spec_helper'

# Records the workspaces dropdown group responses into the repository domain's
# fixture directory, so the repository handlers serve them with no extra wiring.
RSpec.describe 'Repository workspaces dropdown group Integration (GraphQL fixtures)', type: :request,
  feature_category: :workspaces do
  include ApiHelpers
  include GraphqlHelpers
  include JavaScriptFixturesHelpers

  include_context 'with constant modules'

  let_it_be(:user) { create(:user) }
  let_it_be(:group) { create(:group, developers: user) }
  let_it_be(:project) { create(:project, :repository, namespace: group) }

  let_it_be(:agent) do
    create(:ee_cluster_agent, :with_existing_workspaces_agent_config, project: project, created_by_user: user)
  end

  let_it_be(:cluster_agent_mapping) do
    create(:namespace_cluster_agent_mapping, user: user, agent: agent, namespace: group)
  end

  let_it_be(:workspace) do
    create(:workspace, user: user, agent: agent, project: project,
      actual_state: states_module::RUNNING, desired_state: states_module::RUNNING)
  end

  before do
    stub_licensed_features(remote_development: true)
  end

  base_output_path = 'graphql/repository/integration/'
  queries_path = 'workspaces/common/graphql/queries/'

  describe GraphQL::Query do
    it "#{base_output_path}get_project_details.query.graphql.json" do
      query = get_graphql_query_as_string("#{queries_path}get_project_details.query.graphql", ee: true)

      post_graphql(query, current_user: user, variables: { projectFullPath: project.full_path })

      expect_graphql_errors_to_be_empty
      expect(graphql_data.dig('project', 'group', 'fullPath')).to eq(group.full_path)
    end

    it "#{base_output_path}get_workspaces_namespace_cluster_agents.query.graphql.json" do
      query = get_graphql_query_as_string(
        "#{queries_path}get_workspaces_namespace_cluster_agents.query.graphql", ee: true
      )

      post_graphql(query, current_user: user, variables: { namespace: group.full_path })

      expect_graphql_errors_to_be_empty
      expect(graphql_data.dig('namespaceAgents', 'workspacesClusterAgents', 'nodes').size).to eq(1)
    end

    it "#{base_output_path}get_workspaces_organization_cluster_agents.query.graphql.json" do
      query = get_graphql_query_as_string(
        "#{queries_path}get_workspaces_organization_cluster_agents.query.graphql", ee: true
      )

      post_graphql(query, current_user: user,
        variables: { organizationID: project.organization.to_global_id.to_s })

      expect_graphql_errors_to_be_empty
      # The agent is mapped to the group only, so the namespace query alone reports it.
      expect(graphql_data.dig('organizationAgents', 'workspacesClusterAgents', 'nodes')).to be_empty
    end

    it "#{base_output_path}user_workspaces_list.query.graphql.json" do
      query = get_graphql_query_as_string("#{queries_path}user_workspaces_list.query.graphql", ee: true)

      post_graphql(query, current_user: user, variables: {
        first: 20,
        includeActualStates: [states_module::RUNNING],
        projectIds: [project.to_global_id.to_s]
      })

      expect_graphql_errors_to_be_empty
      expect(graphql_data.dig('currentUser', 'workspaces', 'nodes', 0, 'actualState')).to eq(states_module::RUNNING)
    end
  end

  describe GraphQL::Query, 'mutations' do
    it "#{base_output_path}workspace_update.mutation.graphql.json" do
      mutation = get_graphql_query_as_string(
        'workspaces/common/graphql/mutations/workspace_update.mutation.graphql', ee: true
      )

      post_graphql(mutation, current_user: user, variables: {
        input: { id: workspace.to_global_id.to_s, desiredState: states_module::STOPPED }
      })

      expect_graphql_errors_to_be_empty
      expect(graphql_data.dig('workspaceUpdate', 'errors')).to be_empty
      expect(graphql_data.dig('workspaceUpdate', 'workspace', 'desiredState')).to eq(states_module::STOPPED)
    end
  end
end
