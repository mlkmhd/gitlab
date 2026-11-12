# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'Project.user_access_authorized_agents', feature_category: :deployment_management do
  include GraphqlHelpers

  let_it_be(:organization) { create(:group) }
  let_it_be(:agent_management_project) { create(:project, :private, group: organization) }
  let_it_be(:agent) { create(:cluster_agent, project: agent_management_project) }

  let_it_be(:deployment_project) { create(:project, :private, group: organization) }
  let_it_be(:deployment_developer) { create(:user, developer_of: deployment_project) }
  let_it_be(:deployment_reporter) { create(:user, reporter_of: deployment_project) }
  let_it_be(:instance_admin) { create(:admin) }

  let(:user) { deployment_developer }

  let(:query) do
    %(
      query {
        project(fullPath: "#{deployment_project.full_path}") {
          userAccessAuthorizedAgents {
            nodes {
              agent {
                id
                name
                project {
                  name
                }
              }
              config
            }
          }
        }
      }
    )
  end

  subject { GitlabSchema.execute(query, context: { current_user: user }).as_json }

  context 'with project authorization' do
    let!(:user_access) { create(:agent_user_access_project_authorization, agent: agent, project: deployment_project) }

    it 'returns the authorized agent' do
      authorized_agents = subject.dig('data', 'project', 'userAccessAuthorizedAgents', 'nodes')

      expect(authorized_agents.count).to eq(1)

      authorized_agent = authorized_agents.first

      expect(authorized_agent['agent']['id']).to eq(agent.to_global_id.to_s)
      expect(authorized_agent['agent']['name']).to eq(agent.name)
      expect(authorized_agent['config']).to eq({})
      expect(authorized_agent['agent']['project']).to be_nil # User is not authorized to read other resources.
    end

    context 'when user is developer in the agent management project' do
      before_all do
        agent_management_project.add_developer(deployment_developer)
      end

      it 'returns the project information as well' do
        authorized_agent = subject.dig('data', 'project', 'userAccessAuthorizedAgents', 'nodes').first

        expect(authorized_agent['agent']['project']['name']).to eq(agent_management_project.name)
      end
    end

    context 'when user is reporter' do
      let(:user) { deployment_reporter }

      it 'returns nothing' do
        expect(subject['data']['project']['userAccessAuthorizedAgents']).to be_nil
      end
    end

    context 'when user is an instance administrator without membership' do
      let(:user) { instance_admin }

      context 'when admin mode is enabled', :enable_admin_mode do
        it 'returns the authorized agent' do
          authorized_agents = subject.dig('data', 'project', 'userAccessAuthorizedAgents', 'nodes')

          expect(authorized_agents.count).to eq(1)

          authorized_agent = authorized_agents.first

          expect(authorized_agent['agent']['id']).to eq(agent.to_global_id.to_s)
          expect(authorized_agent['agent']['name']).to eq(agent.name)
          expect(authorized_agent['config']).to eq({})
          expect(authorized_agent['agent']['project']['name']).to eq(agent_management_project.name)
        end
      end

      context 'when admin mode is disabled' do
        it 'returns nothing' do
          expect(subject.dig('data', 'project')).to be_nil
        end
      end
    end
  end

  context 'with group authorization' do
    context "when the agent is authorized to the group the agent's project belongs to" do
      # Authorize the agent to the organization, that the agent's project belongs to
      let!(:user_access) { create(:agent_user_access_group_authorization, agent: agent, group: organization) }

      before_all do
        organization.add_developer(deployment_developer)
        organization.add_reporter(deployment_reporter)
      end

      it 'returns the authorized agent' do
        authorized_agents = subject.dig('data', 'project', 'userAccessAuthorizedAgents', 'nodes')
        expect(authorized_agents.count).to eq(1)

        authorized_agent = authorized_agents.first
        expect(authorized_agent['agent']['id']).to eq(agent.to_global_id.to_s)
        expect(authorized_agent['agent']['name']).to eq(agent.name)
        expect(authorized_agent['config']).to eq({})
        expect(authorized_agent['agent']['project']['name']).to eq(agent_management_project.name)
      end

      context 'when user is reporter' do
        let(:user) { deployment_reporter }

        it 'returns nothing' do
          expect(subject['data']['project']['userAccessAuthorizedAgents']).to be_nil
        end
      end

      context 'when user is an instance administrator without membership' do
        let(:user) { instance_admin }

        context 'when admin mode is enabled', :enable_admin_mode do
          it 'returns the authorized agent' do
            authorized_agents = subject.dig('data', 'project', 'userAccessAuthorizedAgents', 'nodes')

            expect(authorized_agents.count).to eq(1)

            authorized_agent = authorized_agents.first

            expect(authorized_agent['agent']['id']).to eq(agent.to_global_id.to_s)
            expect(authorized_agent['agent']['name']).to eq(agent.name)
            expect(authorized_agent['config']).to eq({})
            expect(authorized_agent['agent']['project']['name']).to eq(agent_management_project.name)
          end
        end

        context 'when admin mode is disabled' do
          it 'returns nothing' do
            expect(subject.dig('data', 'project')).to be_nil
          end
        end
      end
    end

    context "when the agent is authorized to the sub-group" do
      let_it_be(:sub_group) { create(:group, :private, parent: organization) }

      # Authorize the agent to the sub-group of the organization, that the agent's project belongs to
      let!(:user_access) { create(:agent_user_access_group_authorization, agent: agent, group: sub_group) }

      before_all do
        sub_group.add_developer(deployment_developer)
        sub_group.add_reporter(deployment_reporter)
      end

      it 'returns empty authorized agents' do
        authorized_agents = subject.dig('data', 'project', 'userAccessAuthorizedAgents', 'nodes')
        expect(authorized_agents).to be_empty
      end

      context 'when user is an instance administrator with admin mode enabled', :enable_admin_mode do
        let(:user) { instance_admin }

        it 'returns empty authorized agents' do
          authorized_agents = subject.dig('data', 'project', 'userAccessAuthorizedAgents', 'nodes')
          expect(authorized_agents).to be_empty
        end
      end

      context 'when user is reporter' do
        let(:user) { deployment_reporter }

        it 'returns nothing' do
          expect(subject['data']['project']['userAccessAuthorizedAgents']).to be_nil
        end
      end
    end

    context "when two agents are authorized, one to the parent group and one to the sub-group" do
      # Authorize the agent to the group that the agent's project belongs to
      let!(:user_access) { create(:agent_user_access_group_authorization, agent: agent, group: organization) }

      let_it_be(:sub_group) { create(:group, :private, parent: organization) }
      let_it_be(:sub_group_project) { create(:project, :private, group: sub_group) }
      let_it_be(:sub_group_agent) { create(:cluster_agent, project: sub_group_project) }

      # Authorize the sub-group agent to the parent group
      let!(:user_access_sub_group_agent) do
        create(:agent_user_access_group_authorization, agent: sub_group_agent, group: organization)
      end

      before_all do
        organization.add_developer(deployment_developer)
        organization.add_reporter(deployment_reporter)
      end

      it 'returns both authorized agents' do
        authorized_agents = subject.dig('data', 'project', 'userAccessAuthorizedAgents', 'nodes')
        expect(authorized_agents.count).to eq(2)

        authorized_agents.each do |authorized_agent|
          expect(authorized_agent['agent']['id']).to be_in([agent.to_global_id.to_s, sub_group_agent.to_global_id.to_s])
        end
      end

      context 'when user is reporter' do
        let(:user) { deployment_reporter }

        it 'returns nothing' do
          expect(subject['data']['project']['userAccessAuthorizedAgents']).to be_nil
        end
      end
    end
  end

  context 'when deployment project is not authorized to user_access to the agent' do
    it 'returns empty' do
      authorized_agents = subject.dig('data', 'project', 'userAccessAuthorizedAgents', 'nodes')

      expect(authorized_agents).to be_empty
    end
  end

  context 'with a fine-grained personal access token' do
    let_it_be(:user_access) do
      create(:agent_user_access_project_authorization, agent: agent, project: deployment_project,
        config: { 'access_as' => { 'agent' => {} } })
    end

    let(:request) { post_graphql(query, token: { personal_access_token: pat }) }

    context 'when reading the authorized agents of the project' do
      let(:boundary_object) { deployment_project }

      it_behaves_like 'authorizing granular token permissions for GraphQL with a skipped child type',
        [:read_project, :read_cluster_agent] do
        let(:skipped_data_path) { [:project, :user_access_authorized_agents, :nodes, 0, :config] }
      end

      it_behaves_like 'denying a granular token that only authorizes the parent of a field', :read_project do
        let(:parent_data_path) { %i[project] }
        let(:field_data_path) { %i[project user_access_authorized_agents] }
      end

      context 'when the agent belongs to another project the user can read' do
        let(:node_data_path) { [:project, :user_access_authorized_agents, :nodes, 0] }
        let(:agent_project_scopes) { [] }
        let(:pat) do
          create(:granular_pat, user: user, boundary: ::Authz::Boundary.for(deployment_project),
            permissions: %w[read_project read_cluster_agent], additional_scopes: agent_project_scopes)
        end

        before_all do
          agent_management_project.add_developer(deployment_developer)
        end

        it 'returns the authorization without the agent', :aggregate_failures do
          request

          expect(graphql_errors).to be_nil
          expect(graphql_data_at(*node_data_path, :config)).to be_present
          expect(graphql_data_at(*node_data_path, :agent)).to be_nil
        end

        context 'when the token can also read the cluster agents of that project' do
          let(:agent_project_scopes) do
            [{ boundary: ::Authz::Boundary.for(agent_management_project), permissions: %w[read_cluster_agent] }]
          end

          it 'returns the agent', :aggregate_failures do
            request

            expect(graphql_errors).to be_nil
            expect(graphql_data_at(*node_data_path, :agent)).to include('id' => agent.to_global_id.to_s,
              'name' => agent.name)
          end
        end
      end
    end

    context 'when reading the user access configuration of the agent' do
      let_it_be(:agent_developer) { create(:user, developer_of: agent_management_project) }

      let(:user) { agent_developer }
      let(:boundary_object) { agent_management_project }
      let(:query) do
        graphql_query_for(:project, { full_path: agent_management_project.full_path },
          query_graphql_field(:cluster_agent, { name: agent.name }, 'userAccessAuthorizations { config }'))
      end

      it_behaves_like 'authorizing granular token permissions for GraphQL with a skipped child type',
        [:read_project, :read_cluster_agent] do
        let(:skipped_data_path) { %i[project cluster_agent user_access_authorizations config] }
      end
    end
  end
end
