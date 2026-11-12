# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'querying duoMcpServerNames on a group', feature_category: :duo_agent_platform do
  include GraphqlHelpers

  let_it_be(:group, freeze: false) do
    create(:group) { |g| g.namespace_settings.update!(duo_features_enabled: true) }
  end

  let_it_be(:organization) { group.organization }
  let_it_be(:current_user) { create(:user, maintainer_of: group, organizations: [organization]) }

  def query_field(user: current_user)
    result = GitlabSchema.execute(%(
      query {
        group(fullPath: "#{group.full_path}") {
          duoMcpServerNames
        }
      }
    ), context: { current_user: user }).as_json

    result.dig('data', 'group', 'duoMcpServerNames')
  end

  def agent_definition(server_ids)
    { 'system_prompt' => 'Test prompt', 'tools' => [], 'user_prompt' => '', 'mcp_servers' => server_ids }
  end

  before_all do
    group.ai_settings.update!(duo_workflow_mcp_enabled: true)
  end

  before do
    # Stub the entitlement seams so the real :read_ai_catalog_mcp_server policy grant is exercised.
    allow(::Gitlab::Llm::StageCheck).to receive(:available?).and_return(true)
    allow(::Ai::Catalog).to receive(:mcp_servers_available?).and_return(true)
  end

  it 'is empty when no configured agent uses an MCP server' do
    expect(query_field).to eq([])
  end

  context 'when configured agents use MCP servers' do
    let_it_be(:server) { create(:ai_catalog_mcp_server, organization: organization, name: 'Linear') }
    let_it_be(:shared_server) { create(:ai_catalog_mcp_server, organization: organization, name: 'Atlassian') }

    before_all do
      [[server.id, shared_server.id], [shared_server.id]].each do |server_ids|
        agent = create(:ai_catalog_agent, organization: organization)
        create(:ai_catalog_agent_version, item: agent, definition: agent_definition(server_ids))
        create(:ai_catalog_item_consumer, group: group, item: agent)
      end

      group.namespace_settings.update!(duo_custom_agents_enabled: true)
    end

    it 'lists each server of the configured agents once, sorted by name' do
      expect(query_field).to eq(%w[Atlassian Linear])
    end
  end

  # Which MCP servers a group's agents use is not public information. The
  # reader is a maintainer, so the group itself resolves and the nil can only
  # come from the field-level authorization.
  context 'when the root namespace has MCP disabled' do
    before do
      group.ai_settings.update!(duo_workflow_mcp_enabled: false)
    end

    after do
      group.ai_settings.update!(duo_workflow_mcp_enabled: true)
    end

    it 'redacts the field for a member who can read the group' do
      result = GitlabSchema.execute(%(
        query {
          group(fullPath: "#{group.full_path}") {
            id
            duoMcpServerNames
          }
        }
      ), context: { current_user: current_user }).as_json.dig('data', 'group')

      expect(result['id']).to be_present
      expect(result['duoMcpServerNames']).to be_nil
    end
  end

  context 'when the group is a subgroup' do
    let_it_be(:subgroup) { create(:group, parent: group) }

    # The subgroup itself always resolves here, so a nil can only come from the field.
    def query_subgroup_field(user: current_user)
      result = GitlabSchema.execute(%(
        query {
          group(fullPath: "#{subgroup.full_path}") {
            id
            duoMcpServerNames
          }
        }
      ), context: { current_user: user }).as_json.dig('data', 'group')

      expect(result['id']).to be_present

      result['duoMcpServerNames']
    end

    it 'is empty when no agent enabled for all projects of the top-level group uses an MCP server' do
      expect(query_subgroup_field).to eq([])
    end

    context 'when the top-level group has direct and inherited agents using MCP servers' do
      let_it_be(:direct_server) { create(:ai_catalog_mcp_server, organization: organization, name: 'Linear') }
      let_it_be(:inherited_server) { create(:ai_catalog_mcp_server, organization: organization, name: 'Jira') }

      before_all do
        direct_agent = create(:ai_catalog_agent, organization: organization)
        create(:ai_catalog_agent_version, item: direct_agent, definition: agent_definition([direct_server.id]))
        create(:ai_catalog_item_consumer, group: group, item: direct_agent)

        inherited_agent = create(:ai_catalog_agent, :public, organization: organization)
        create(:ai_catalog_agent_version, item: inherited_agent, definition: agent_definition([inherited_server.id]))
        create(:ai_catalog_item_consumer, :inheritance, group: group, item: inherited_agent, service_account: nil)

        group.namespace_settings.update!(duo_custom_agents_enabled: true)
      end

      it "lists only the servers of the agents that run in the subgroup's projects" do
        expect(query_subgroup_field).to eq(%w[Jira])
      end

      it 'keeps listing every server on the top-level group' do
        expect(query_field).to eq(%w[Jira Linear])
      end

      it 'resolves for an owner of the subgroup who is not a member of the top-level group' do
        create(:project, group: subgroup)
        subgroup_owner = create(:user, owner_of: subgroup, organizations: [organization])

        expect(query_subgroup_field(user: subgroup_owner)).to eq(%w[Jira])
      end

      it 'does not list a server blocked on the top-level group' do
        create(:ai_catalog_mcp_server_block, organization: organization, namespace: group, mcp_server: inherited_server)

        expect(query_subgroup_field).to eq([])
      end

      context 'when the ai_catalog_group_inherited_consumers feature flag is disabled' do
        before do
          stub_feature_flags(ai_catalog_group_inherited_consumers: false)
        end

        it 'is null and does not read the configured agents' do
          expect(::Ai::Catalog::ItemConsumersFinder).not_to receive(:new)

          expect(query_subgroup_field).to be_nil
        end
      end
    end
  end

  it 'can be requested for at most 10 groups in one query', :aggregate_failures do
    query_for = ->(count) do
      aliases = Array.new(count) { |i| %(g#{i}: group(fullPath: "#{group.full_path}") { duoMcpServerNames }) }
      GitlabSchema.execute("query { #{aliases.join("\n")} }", context: { current_user: current_user }).as_json
    end

    expect(query_for.call(10)['errors']).to be_nil
    expect(query_for.call(11)['errors'].pluck('message'))
      .to include('"duoMcpServerNames" field can be requested only for 10 Group(s) at a time.')
  end

  it 'is not resolved unless it is requested' do
    expect(::Ai::DuoWorkflow::GroupReadiness).not_to receive(:new)

    GitlabSchema.execute(%(
      query { group(fullPath: "#{group.full_path}") { id } }
    ), context: { current_user: current_user })
  end
end
