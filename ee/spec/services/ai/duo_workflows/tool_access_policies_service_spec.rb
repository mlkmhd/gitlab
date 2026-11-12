# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Ai::DuoWorkflows::ToolAccessPoliciesService, feature_category: :duo_agent_platform do
  let_it_be(:group) { create(:group) }
  let_it_be(:project) { create(:project, group: group) }
  let_it_be(:other_group) { create(:group) }
  let_it_be(:user) { create(:user, developer_of: project) }

  let(:workflow) { create(:duo_workflows_workflow, user: user, project: project) }
  let(:mcp_config_service) { instance_double(Ai::DuoWorkflows::McpConfigService, preapproved_tool_names: []) }

  subject(:policies) do
    described_class.new(
      workflow: workflow,
      root_namespace: other_group,
      project: nil,
      environment: nil,
      mcp_config_service: mcp_config_service
    ).execute
  end

  context 'when the workflow has no container' do
    before do
      allow(workflow).to receive(:resource_parent).and_return(nil)
    end

    it { is_expected.to eq(allow: [], ask: [], deny: []) }
  end

  context 'when the surface is ungoverned' do
    before do
      allow(Ai::ToolRules::GovernanceSurface).to receive_messages(for: :ide, ungoverned?: true)
      allow(Ai::ToolRules::ResolutionService).to receive(:new)
        .with(namespace: group, surface: Ai::ToolRules::GovernanceSurface::LOCAL, project: project)
        .and_return(instance_double(Ai::ToolRules::ResolutionService,
          first_party_verdicts: { 'mcp__duo__review' => 'deny' }))
    end

    it 'returns empty lists with the first-party verdicts' do
      expect(policies).to eq(allow: [], ask: [], deny: [], first_party_tools: { 'mcp__duo__review' => 'deny' })
    end
  end

  context 'when governance resolves a verdict' do
    before do
      allow(Ai::ToolRules::GovernanceSurface).to receive_messages(for: nil, ungoverned?: false)
    end

    it "resolves from the workflow's own container, not the requested root namespace" do
      expect(Ai::ToolRules::ResolutionService).to receive(:new)
        .with(namespace: group, surface: :web, project: project)
        .and_return(instance_double(Ai::ToolRules::ResolutionService, execute: ServiceResponse.success(payload: {
          pre_approved_tools: %w[get_issue], ask_tools: [], denied_tools: %w[run_command],
          first_party_tools: { 'mcp__duo__review' => 'ask' }
        })))

      expect(policies).to eq(
        allow: %w[get_issue], ask: [], deny: %w[run_command],
        first_party_tools: { 'mcp__duo__review' => 'ask' }, ceiling: true
      )
    end

    context 'when the requested project fails to resolve' do
      let_it_be(:requested_project) { create(:project, group: group) }

      subject(:policies) do
        described_class.new(
          workflow: workflow,
          root_namespace: other_group,
          project: requested_project,
          environment: nil,
          mcp_config_service: mcp_config_service
        ).execute
      end

      it "keeps the workflow's own policy" do
        allow(Ai::ToolRules::ResolutionService).to receive(:new)
          .with(namespace: group, surface: :web, project: project)
          .and_return(instance_double(Ai::ToolRules::ResolutionService, execute: ServiceResponse.success(payload: {
            pre_approved_tools: %w[get_issue], ask_tools: [], denied_tools: %w[run_command], first_party_tools: {}
          })))
        allow(Ai::ToolRules::ResolutionService).to receive(:new)
          .with(namespace: group, surface: :web, project: requested_project)
          .and_return(instance_double(Ai::ToolRules::ResolutionService,
            execute: ServiceResponse.error(message: 'failed')))

        expect(policies).to eq(
          allow: %w[get_issue], ask: [], deny: %w[run_command], first_party_tools: {}, ceiling: true
        )
      end
    end

    context 'without a workflow' do
      let_it_be(:subgroup) { create(:group, parent: group) }

      let(:request_namespace) { subgroup }

      subject(:policies) do
        described_class.new(
          workflow: nil,
          root_namespace: group,
          project: nil,
          environment: nil,
          mcp_config_service: mcp_config_service,
          request_namespace: request_namespace
        ).execute
      end

      before do
        stub_feature_flags(duo_workflow_governance_ceiling: subgroup)
        allow(Ai::ToolRules::ResolutionService).to receive(:new)
          .with(namespace: group, surface: :web, project: nil)
          .and_return(instance_double(Ai::ToolRules::ResolutionService, execute: ServiceResponse.success(payload: {
            pre_approved_tools: [], ask_tools: [], denied_tools: [], first_party_tools: {}
          })))
      end

      it 'follows the request namespace for a subgroup rollout' do
        expect(policies).to include(ceiling: true)
      end

      context 'when the request names no namespace' do
        let(:request_namespace) { nil }

        it 'checks only the root namespace' do
          expect(policies).not_to have_key(:ceiling)
        end
      end
    end
  end

  describe 'the promote list' do
    let_it_be_with_reload(:local_group) { create(:group) }
    let_it_be_with_reload(:local_project) { create(:project, group: local_group) }
    let_it_be_with_reload(:sibling_project) { create(:project, group: local_group) }

    let(:environment) { :ide }
    let(:workflow) { create(:duo_workflows_workflow, user: user, project: local_project, environment: environment) }
    let(:requested_project) { nil }

    subject(:policies) do
      described_class.new(
        workflow: workflow,
        root_namespace: local_group,
        project: requested_project,
        environment: nil,
        mcp_config_service: mcp_config_service
      ).execute
    end

    before do
      local_project.project_setting.update!(duo_auto_mode_enabled: true)
    end

    it 'signs the tools left at a default of ask' do
      expect(policies[:promote]).to include('run_command', 'edit_file', 'run_git_command', 'create_issue')
    end

    it 'shares no name with any other list', :aggregate_failures do
      stub_feature_flags(duo_cli_first_party_tools: local_group)
      create(:ai_tool_rule, namespace: local_group, tool_name: 'run_git_command', local_access: :ask)
      create(:ai_tool_rule, namespace: local_group, tool_name: 'mkdir', local_access: :deny)
      create(:ai_tool_rule, namespace: local_group, tool_name: 'create_issue', local_access: :allow)

      expect(policies[:promote]).not_to be_empty
      expect(policies[:promote]).not_to include('run_git_command', 'mkdir', 'create_issue')
      expect(policies[:promote] & policies[:allow]).to be_empty
      expect(policies[:promote] & policies[:ask]).to be_empty
      expect(policies[:promote] & policies[:deny]).to be_empty
      expect(policies[:promote] & policies[:first_party_tools].keys).to be_empty
    end

    context 'when MCP pre-approves a default ask' do
      let(:mcp_config_service) do
        instance_double(Ai::DuoWorkflows::McpConfigService, preapproved_tool_names: %w[run_command])
      end

      it 'keeps it in allow only', :aggregate_failures do
        expect(policies[:allow]).to include('run_command')
        expect(policies[:promote]).not_to include('run_command')
      end
    end

    context 'when a consenting requested project allows a tool' do
      let(:requested_project) { sibling_project }

      before do
        sibling_project.project_setting.update!(duo_auto_mode_enabled: true)
        create(:ai_tool_rule, namespace: local_group, project: sibling_project, tool_name: 'run_command',
          local_access: :allow)
      end

      it 'neither pre-approves nor promotes it', :aggregate_failures do
        expect(policies[:allow]).not_to include('run_command')
        expect(policies[:promote]).to include('edit_file')
        expect(policies[:promote]).not_to include('run_command')
      end
    end

    context 'when the workflow runs in a group' do
      let(:workflow) do
        create(:duo_workflows_workflow, user: user, project: nil, namespace: local_group, environment: environment)
      end

      it 'omits the list without the group consent' do
        expect(policies).not_to have_key(:promote)
      end

      it 'signs the list with the group consent' do
        local_group.namespace_settings.update!(duo_auto_mode_enabled: true)

        expect(policies[:promote]).to include('run_command')
      end
    end

    context 'on a web surface' do
      let(:environment) { :web }

      it { is_expected.not_to have_key(:promote) }
    end

    context 'without a workflow' do
      before do
        local_group.namespace_settings.update!(duo_auto_mode_enabled: true)
      end

      it 'omits the list', :aggregate_failures do
        policies = described_class.new(
          workflow: nil, root_namespace: local_group, project: local_project, environment: 'ide',
          mcp_config_service: mcp_config_service
        ).execute

        expect(policies[:allow]).to be_present
        expect(policies).not_to have_key(:promote)
      end
    end

    context 'when duo_auto_mode_promotion is disabled' do
      before do
        stub_feature_flags(duo_auto_mode_promotion: false)
      end

      it { is_expected.not_to have_key(:promote) }
    end
  end
end
