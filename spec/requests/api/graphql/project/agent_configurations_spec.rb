# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'Project.agent_configurations', feature_category: :deployment_management do
  include GraphqlHelpers

  let_it_be(:project) { create(:project, :private) }
  let_it_be(:user) { create(:user, developer_of: project) }

  let(:query) do
    graphql_query_for(:project, { full_path: project.full_path }, query_nodes(:agent_configurations, :agent_name))
  end

  let(:boundary_object) { project }
  let(:request) { post_graphql(query, token: { personal_access_token: pat }) }

  let(:config_file) { Gitlab::Agent::ConfigurationProject::Rpc::AgentConfigFile.new(agent_name: 'my-agent') }

  before do
    allow(Gitlab::Kas::Client).to receive(:new)
      .and_return(instance_double(Gitlab::Kas::Client, list_agent_config_files: [config_file]))
  end

  it_behaves_like 'authorizing granular token permissions for GraphQL with a skipped child type',
    [:read_project, :read_cluster_agent] do
    let(:skipped_data_path) { [:project, :agent_configurations, :nodes, 0, :agent_name] }
  end

  it_behaves_like 'denying a granular token that only authorizes the parent of a field', :read_project do
    let(:parent_data_path) { %i[project] }
    let(:field_data_path) { %i[project agent_configurations] }
  end
end
