# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'Querying the tool access policies of a Duo Workflow', :aggregate_failures,
  feature_category: :duo_agent_platform do
  include GraphqlHelpers

  let_it_be(:ai_settings, freeze: false) { create(:namespace_ai_settings, duo_workflow_mcp_enabled: true) }
  let_it_be(:group, freeze: false) { create(:group, ai_settings: ai_settings) }
  let_it_be(:project) { create(:project, group: group) }
  let_it_be(:user) { create(:user, maintainer_of: project) }
  let_it_be(:workflow) do
    create(:duo_workflows_workflow, user: user, project: project,
      ai_catalog_item_version_id: create(:ai_catalog_item_version).id)
  end

  let(:current_user) { user }
  let(:field) { 'toolAccessPolicies' }
  let(:query) do
    graphql_query_for(
      'duoWorkflowWorkflows',
      { workflow_id: workflow.to_global_id.to_s },
      "nodes { #{field} }"
    )
  end

  def returned_policies
    post_graphql(query, current_user: current_user)

    expect(response).to have_gitlab_http_status(:success)
    expect(graphql_errors).to be_nil

    graphql_data.dig('duoWorkflowWorkflows', 'nodes')&.first&.fetch('toolAccessPolicies')
  end

  before do
    allow(::Gitlab::Llm::StageCheck).to receive(:available?).with(any_args).and_return(true)
    # rubocop:disable RSpec/AnyInstanceOf -- not the next instance
    allow_any_instance_of(User).to receive_messages(allowed_to_use?: true, allowed_to_use_for_resource?: true)
    # rubocop:enable RSpec/AnyInstanceOf

    allow(Ai::ToolRules::GovernanceSurface).to receive_messages(for: :web, ungoverned?: false)
    allow(Ai::ToolRules::ResolutionService).to receive(:new)
      .with(namespace: group, surface: :web, project: project)
      .and_return(instance_double(Ai::ToolRules::ResolutionService, execute: ServiceResponse.success(payload: {
        pre_approved_tools: %w[get_issue], ask_tools: %w[read_file], denied_tools: %w[run_command],
        first_party_tools: { 'mcp__duo__review' => 'ask' }
      })))
    allow_next_instance_of(Ai::DuoWorkflows::McpConfigService) do |service|
      allow(service).to receive(:preapproved_tool_names).and_return(%w[gitlab_search])
    end
  end

  it 'returns the policy resolved from the workflow' do
    expect(returned_policies).to eq(
      'allow' => %w[get_issue gitlab_search],
      'ask' => %w[read_file],
      'deny' => %w[run_command],
      'first_party_tools' => { 'mcp__duo__review' => 'ask' },
      'ceiling' => true
    )
  end

  it 'returns the promote list on a local surface where auto mode is consented' do
    allow(Ai::ToolRules::GovernanceSurface).to receive_messages(for: :ide, ungoverned?: false)
    allow(Ai::ToolRules::ResolutionService).to receive(:new)
      .with(namespace: group, surface: :ide, project: project)
      .and_return(instance_double(Ai::ToolRules::ResolutionService, execute: ServiceResponse.success(payload: {
        pre_approved_tools: [], ask_tools: [], denied_tools: [], first_party_tools: {},
        default_ask_tools: %w[edit_file run_command]
      })))
    allow(Ai::DuoSettings::AutoMode).to receive(:consented?).with(container: project).and_return(true)

    expect(returned_policies).to include('promote' => %w[edit_file run_command])
  end

  it "does not return another user's workflow" do
    post_graphql(query, current_user: create(:user, developer_of: project))

    expect(graphql_errors).to contain_exactly(include('message' => 'Workflow not found'))
  end

  it 'returns the policy for an ai_workflows OAuth token' do
    token = create(:oauth_access_token, user: user, scopes: [:ai_workflows])

    post_graphql(query, token: { oauth_access_token: token })

    expect(graphql_errors).to be_nil
    expect(graphql_data.dig('duoWorkflowWorkflows', 'nodes', 0, 'toolAccessPolicies')).to include('ceiling' => true)
  end

  it "returns the policy for the flow's service account acting for the user" do
    service_account = create(:user, :service_account, developer_of: project, composite_identity_enforced: true)
    token = create(:oauth_access_token, user: service_account, scopes: ['ai_workflows', "user:#{user.id}"])

    post_graphql(query, token: { oauth_access_token: token })

    expect(graphql_errors).to be_nil
    expect(graphql_data.dig('duoWorkflowWorkflows', 'nodes', 0, 'toolAccessPolicies')).to include('ceiling' => true)
  end

  it "does not return the policy to the service account acting for another user" do
    service_account = create(:user, :service_account, developer_of: project, composite_identity_enforced: true)
    other_user = create(:user, developer_of: project)
    token = create(:oauth_access_token, user: service_account, scopes: ['ai_workflows', "user:#{other_user.id}"])

    post_graphql(query, token: { oauth_access_token: token })

    expect(graphql_errors).to contain_exactly(include('message' => 'Workflow not found'))
  end

  it 'returns nothing to another member who can read a pipeline session' do
    pipeline_workflow = create(:duo_workflows_workflow, user: user, project: project, environment: :web)
    query = graphql_query_for('duoWorkflowWorkflows', { workflow_id: pipeline_workflow.to_global_id.to_s },
      "nodes { #{field} }")

    post_graphql(query, current_user: create(:user, developer_of: project))

    expect(graphql_data.dig('duoWorkflowWorkflows', 'nodes', 0)).to include('toolAccessPolicies' => nil)
  end

  it 'can be requested for one session at a time' do
    create(:duo_workflows_workflow, user: user, project: project)
    list_query = graphql_query_for('duoWorkflowWorkflows', {}, "nodes { #{field} }")

    post_graphql(list_query, current_user: user)

    expect(graphql_errors).to include(include('message' => include('can be requested only for 1')))
  end

  it 'builds the MCP pre-approvals from the workflow' do
    expect(Ai::DuoWorkflows::McpConfigService).to receive(:new).with(
      user, nil,
      workflow_definition: workflow.workflow_definition,
      ai_catalog_item_version_id: workflow.ai_catalog_item_version_id
    ).and_call_original

    returned_policies
  end

  it 'returns empty lists and the first-party verdicts when the surface is not governed' do
    allow(Ai::ToolRules::GovernanceSurface).to receive(:ungoverned?).and_return(true)
    allow(Ai::ToolRules::ResolutionService).to receive(:new)
      .with(namespace: group, surface: Ai::ToolRules::GovernanceSurface::LOCAL, project: project)
      .and_return(instance_double(Ai::ToolRules::ResolutionService,
        first_party_verdicts: { 'mcp__duo__review' => 'deny' }))

    expect(returned_policies).to eq(
      'allow' => [], 'ask' => [], 'deny' => [], 'first_party_tools' => { 'mcp__duo__review' => 'deny' }
    )
  end

  it 'leaves out ceiling when duo_workflow_governance_ceiling is disabled' do
    stub_feature_flags(duo_workflow_governance_ceiling: false)

    expect(returned_policies).not_to have_key('ceiling')
  end

  context 'with a projectId' do
    let_it_be(:other_project) { create(:project, group: group) }

    let(:field) { "toolAccessPolicies(projectId: \"#{requested_project.to_global_id}\")" }
    let(:requested_project) { other_project }

    before do
      allow(Ai::ToolRules::ResolutionService).to receive(:new)
        .with(namespace: group, surface: :web, project: other_project)
        .and_return(instance_double(Ai::ToolRules::ResolutionService, execute: ServiceResponse.success(payload: {
          pre_approved_tools: [], ask_tools: [], denied_tools: %w[get_issue],
          first_party_tools: { 'mcp__duo__review' => 'deny' }
        })))
    end

    it 'applies the stricter rules of a project the user can read' do
      other_project.add_developer(user)

      expect(returned_policies).to include('allow' => %w[gitlab_search], 'deny' => %w[run_command get_issue])
    end

    context 'when the project is pending deletion' do
      let_it_be(:requested_project) { create(:project, group: group, pending_delete: true, developers: user) }

      it 'ignores it' do
        expect(returned_policies).to include('allow' => %w[get_issue gitlab_search], 'deny' => %w[run_command])
      end
    end

    it 'ignores a project the user cannot read' do
      expect(returned_policies).to include('allow' => %w[get_issue gitlab_search], 'deny' => %w[run_command])
    end

    context 'when the project is outside the workflow root namespace' do
      let_it_be(:requested_project) { create(:project, developers: user) }

      it 'ignores it' do
        expect(returned_policies).to include('allow' => %w[get_issue gitlab_search], 'deny' => %w[run_command])
      end
    end

    context 'when the project does not exist' do
      let(:field) { "toolAccessPolicies(projectId: \"gid://gitlab/Project/#{non_existing_record_id}\")" }

      it 'ignores it' do
        expect(returned_policies).to include('allow' => %w[get_issue gitlab_search], 'deny' => %w[run_command])
      end
    end
  end
end
