# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Ai::Catalog::ResolveWorkflowItemsService, feature_category: :ai_catalog_curation do
  let_it_be(:group) { create(:group) }
  let_it_be(:project) { create(:project, group: group) }
  let_it_be(:user) { create(:user, developer_of: project) }

  let_it_be_with_reload(:flow) { create(:ai_catalog_flow, :public, project: project) }
  # Reloaded too: it holds the same Ruby object as `flow`, so a mutation of
  # `flow` in one example would otherwise be visible through it in the next.
  let_it_be_with_reload(:item_version) do
    create(:ai_catalog_flow_version, :released, item: flow, version: '1.0.0')
  end

  let_it_be_with_reload(:agent) { create(:ai_catalog_agent, :public, project: project) }
  let_it_be_with_reload(:agent_version) do
    create(:ai_catalog_agent_version, :released, item: agent, version: '2.0.0')
  end

  let_it_be_with_reload(:dependency) do
    create(:ai_catalog_item_version_dependency,
      ai_catalog_item_version: item_version, dependency: agent, dependency_version: agent_version)
  end

  let(:workflow) do
    build_stubbed(:duo_workflows_workflow, user: user, project: project, ai_catalog_item_version: item_version)
  end

  subject(:response) { described_class.new(workflow: workflow, current_user: user).execute }

  before do
    stub_application_setting(instance_level_ai_beta_features_enabled: true)
  end

  def sub_item
    response.payload[:item][:sub_items].first
  end

  describe '#execute' do
    it 'returns the flow with its agents' do
      expect(response).to be_success
      expect(response.payload[:schema_version]).to eq(1)

      item = response.payload[:item]
      expect(item).to include(
        item_type: 'flow', item_id: flow.id.to_s, version: '1.0.0', definition_kind: 'inline'
      )
      expect(item[:definition]).to eq(item_version.flow_config)
      expect(item[:sub_items_skipped_reason]).to be_nil
      expect(item[:sub_items]).to contain_exactly(
        a_hash_including(
          item_type: 'agent',
          item_id: agent.id.to_s,
          version: '2.0.0',
          name: agent.name,
          definition_kind: 'inline',
          definition: { prompt: 'Talk like a pirate!', toolset: [Ai::Catalog::BuiltInTool.find(1).name], mcp_tools: [] }
        )
      )
    end

    it 'records the resolution', :clean_gitlab_redis_shared_state do
      expect { response }
        .to trigger_internal_events('resolve_ai_catalog_flow_sub_items')
        .with(
          user: user,
          project: project,
          category: 'Ai::Catalog::Tracking::WorkflowItemsResolutionRecorder',
          additional_properties: {
            label: 'served', value: 1, refused_count: 0,
            item_type: 'custom_flow', item_version: item_version.version,
            item_schema_version: item_version.def_version, custom_item_id: flow.id
          }
        )
    end

    context 'when the workflow has no saved flow version' do
      let(:workflow) { build_stubbed(:duo_workflows_workflow, user: user, project: project) }

      it 'fails with a missing_catalog_item_version reason' do
        expect(response).to be_error
        expect(response.reason).to eq(:missing_catalog_item_version)
      end
    end

    context 'when the workflow has no project' do
      let(:workflow) do
        build_stubbed(:duo_workflows_workflow, user: user, project: nil, namespace: group,
          ai_catalog_item_version: item_version)
      end

      it 'fails with a missing_catalog_item_version reason' do
        expect(response).to be_error
        expect(response.reason).to eq(:missing_catalog_item_version)
      end
    end

    context 'when the saved item is not a flow' do
      let_it_be(:agent_item_version) { create(:ai_catalog_agent_version, :released, item: agent, version: '9.0.0') }

      let(:workflow) do
        build_stubbed(:duo_workflows_workflow, user: user, project: project,
          ai_catalog_item_version: agent_item_version)
      end

      it 'fails with a missing_catalog_item_version reason' do
        expect(response).to be_error
        expect(response.reason).to eq(:missing_catalog_item_version)
      end
    end

    context 'when the user can no longer read the flow' do
      before do
        allow(Ability).to receive(:allowed?).and_call_original
        allow(Ability).to receive(:allowed?).with(user, :read_ai_catalog_item, flow).and_return(false)
      end

      it 'fails with a root_item_not_readable reason and no payload' do
        expect(response).to be_error
        expect(response.reason).to eq(:root_item_not_readable)
        expect(response.message).not_to include(flow.name)
      end
    end

    context 'when the flow was soft-deleted after the session was created' do
      before do
        flow.update_column(:deleted_at, Time.current)
      end

      it 'fails with a root_item_not_readable reason' do
        expect(response).to be_error
        expect(response.reason).to eq(:root_item_not_readable)
      end
    end

    shared_examples 'a run without sub-agents' do |reason|
      it "returns the flow with no sub-agents and the reason #{reason}" do
        expect(response).to be_success
        expect(response.payload[:item][:sub_items]).to be_empty
        expect(response.payload[:item][:sub_items_skipped_reason]).to eq(reason)
      end

      it 'does not load the dependency rows' do
        expect(Ai::Catalog::ItemVersionDependency).not_to receive(:for_item_version)

        response
      end
    end

    context 'when the feature flag is off' do
      before do
        stub_feature_flags(ai_catalog_flow_agent_references: false)
      end

      it_behaves_like 'a run without sub-agents', 'feature_flag_disabled'
    end

    context 'when experiment and beta features are off for the root group' do
      before do
        allow(group).to receive(:duo_beta_flows_enabled?).and_return(false)
        allow(project).to receive(:root_ancestor).and_return(group)
      end

      it_behaves_like 'a run without sub-agents', 'beta_features_disabled'
    end

    context 'when custom agents are turned off for the root group' do
      before do
        allow(group).to receive(:duo_custom_agents_enabled).and_return(false)
        allow(project).to receive(:root_ancestor).and_return(group)
      end

      it 'refuses the custom agent with a custom_agents_disabled error' do
        expect(response.payload[:item][:sub_items_skipped_reason]).to be_nil
        expect(sub_item).to include(
          item_id: agent.id.to_s,
          name: agent.name,
          error: {
            code: :custom_agents_disabled,
            message: "Agent '#{agent.name}' is a custom agent, and custom agents are turned off"
          }
        )
        expect(sub_item).not_to include(:definition)
      end

      context 'when the agent is a foundational agent' do
        before do
          stub_saas_features(gitlab_duo_saas_only: true)
          allow(::Ai::FoundationalChatAgent).to receive(:find_by).and_call_original
          allow(::Ai::FoundationalChatAgent).to receive(:find_by)
            .with(global_catalog_id: agent.id).and_return(::Ai::FoundationalChatAgent.all.first)
        end

        it 'returns the agent with its definition' do
          expect(sub_item).to include(item_id: agent.id.to_s, definition_kind: 'inline')
          expect(sub_item).not_to include(:error)
        end
      end
    end

    context 'when the user cannot read the agent' do
      before do
        allow(Ability).to receive(:allowed?).and_call_original
        allow(Ability).to receive(:allowed?).with(user, :read_ai_catalog_item, agent).and_return(false)
      end

      it 'returns only the id and version the flow definition already shows, with an unknown_item error' do
        expect(sub_item).to eq(
          item_type: 'agent',
          item_id: agent.id.to_s,
          version: '2.0.0',
          error: {
            code: :unknown_item,
            message: "Agent '#{agent.id}' (version 2.0.0) was not found or you do not have access to it"
          }
        )
      end
    end

    context 'when the agent was soft-deleted after the flow was saved' do
      before do
        agent.update_column(:deleted_at, Time.current)
      end

      it 'returns an unknown_item error without the name or description' do
        expect(sub_item[:error]).to include(code: :unknown_item)
        expect(sub_item).not_to include(:name, :description, :definition)
      end
    end

    context 'when the agent became private in another project' do
      let_it_be(:other_project) { create(:project, group: group) }

      before do
        agent.update_columns(project_id: other_project.id, visibility: :private)
        allow(Ability).to receive(:allowed?).and_call_original
        allow(Ability).to receive(:allowed?).with(user, :read_ai_catalog_item, agent).and_return(true)
      end

      it 'returns the agent with a location error that gives its name' do
        expect(sub_item).to include(name: agent.name, description: agent.description)
        expect(sub_item[:error]).to eq(
          code: :location, message: "Agent '#{agent.name}' is not visible to flows in this project"
        )
        expect(sub_item).not_to have_key(:definition)
      end
    end

    context 'when the agent is less visible than the flow' do
      before do
        agent.update_column(:visibility, :restricted)
        allow(Ability).to receive(:allowed?).and_call_original
        allow(Ability).to receive(:allowed?).with(user, :read_ai_catalog_item, agent).and_return(true)
      end

      it 'returns the agent with a visibility error' do
        expect(sub_item[:error]).to eq(
          code: :visibility,
          message: "Agent '#{agent.name}' must be at least as visible as the flow that references it"
        )
      end
    end

    context 'when the dependency row has no pinned version' do
      before do
        dependency.update_column(:dependency_version_id, nil)
      end

      it 'returns the agent with a nil version and an unknown_version error' do
        expect(sub_item[:version]).to be_nil
        expect(sub_item[:error]).to eq(code: :unknown_version, message: "Agent '#{agent.name}' has no version ")
      end
    end

    context 'when the pinned version is no longer released' do
      before do
        agent_version.update_column(:release_date, nil)
      end

      it 'returns the agent with an unknown_version error' do
        expect(sub_item[:error]).to eq(
          code: :unknown_version, message: "Agent '#{agent.name}' has no version 2.0.0"
        )
      end
    end

    context 'when a referenced agent has no project' do
      let_it_be_with_reload(:orphan_agent) { create(:ai_catalog_agent, :public, project: nil) }
      let_it_be(:orphan_version) do
        create(:ai_catalog_agent_version, :released, item: orphan_agent, version: '1.0.0')
      end

      let_it_be(:orphan_dependency) do
        create(:ai_catalog_item_version_dependency,
          ai_catalog_item_version: item_version, dependency: orphan_agent, dependency_version: orphan_version)
      end

      before do
        allow(Ability).to receive(:allowed?).and_call_original
        allow(Ability).to receive(:allowed?).with(user, :read_ai_catalog_item, orphan_agent).and_return(true)
      end

      it 'resolves it without preloading a namespace for it' do
        orphan = response.payload[:item][:sub_items].find { |item| item[:item_id] == orphan_agent.id.to_s }

        expect(orphan).to have_key(:definition)
      end
    end

    context 'with one good agent and one refused agent' do
      let_it_be_with_reload(:refused_agent) { create(:ai_catalog_agent, :public, project: project) }
      let_it_be(:refused_version) do
        create(:ai_catalog_agent_version, :released, item: refused_agent, version: '1.0.0')
      end

      let_it_be(:refused_dependency) do
        create(:ai_catalog_item_version_dependency,
          ai_catalog_item_version: item_version, dependency: refused_agent, dependency_version: refused_version)
      end

      before do
        allow(Ability).to receive(:allowed?).and_call_original
        allow(Ability).to receive(:allowed?).with(user, :read_ai_catalog_item, refused_agent).and_return(false)
      end

      it 'keeps the good agent and marks the refused one' do
        sub_items = response.payload[:item][:sub_items]

        expect(sub_items.size).to eq(2)
        expect(sub_items.find { |item| item[:item_id] == agent.id.to_s }).to have_key(:definition)
        expect(sub_items.find { |item| item[:item_id] == refused_agent.id.to_s }[:error])
          .to include(code: :unknown_item)
      end

      it 'audits the refused agent' do
        expect(::Gitlab::Audit::Auditor).to receive(:audit).once.with(
          hash_including(
            name: 'ai_catalog_flow_sub_agent_refused',
            author: user,
            scope: project,
            target: workflow,
            additional_details: { item_id: refused_agent.id.to_s, version: '1.0.0', code: :unknown_item }
          )
        )

        response
      end
    end

    context 'when the workflow pins an older flow version' do
      let_it_be_with_reload(:older_version) do
        create(:ai_catalog_flow_version, :released, item: flow, version: '0.9.0')
      end

      let_it_be_with_reload(:older_agent) { create(:ai_catalog_agent, :public, project: project) }
      let_it_be(:older_dependency) do
        create(:ai_catalog_item_version_dependency,
          ai_catalog_item_version: older_version, dependency: older_agent,
          dependency_version: create(:ai_catalog_agent_version, :released, item: older_agent, version: '1.0.0'))
      end

      let(:workflow) do
        build_stubbed(:duo_workflows_workflow, user: user, project: project, ai_catalog_item_version: older_version)
      end

      it 'serves the dependencies of the pinned version, not the latest' do
        item = response.payload[:item]

        expect(item[:version]).to eq('0.9.0')
        expect(item[:sub_items].map { |s| s[:item_id] }).to contain_exactly(older_agent.id.to_s)
      end
    end

    context 'when the agent was hard-deleted after the flow was saved' do
      let_it_be_with_reload(:gone_agent) { create(:ai_catalog_agent, :public, project: project) }

      before do
        create(:ai_catalog_item_version_dependency,
          ai_catalog_item_version: item_version, dependency: gone_agent,
          dependency_version: create(:ai_catalog_agent_version, :released, item: gone_agent, version: '1.0.0'))
        gone_agent.delete
      end

      it 'drops the row with the agent and serves the rest' do
        expect(response.payload[:item][:sub_items].map { |s| s[:item_id] }).to contain_exactly(agent.id.to_s)
      end
    end

    context 'when the dependency rows exceed the per-flow ceiling' do
      before do
        stub_const('Ai::Catalog::Flows::ReferenceLimits::MAX_REFERENCES_PER_KIND', { agent: 1 })
        extra = create(:ai_catalog_agent, :public, project: project)
        create(:ai_catalog_item_version_dependency,
          ai_catalog_item_version: item_version, dependency: extra,
          dependency_version: create(:ai_catalog_agent_version, :released, item: extra, version: '1.0.0'))
      end

      it 'serves every saved row, because the save path is where the ceiling applies' do
        expect(response.payload[:item][:sub_items].size).to eq(2)
      end
    end

    context 'when the agent version has a prompt larger than the payload ceiling' do
      before do
        agent_version.update_column(:definition,
          agent_version.definition.merge('system_prompt' => 'x' * 200.kilobytes))
      end

      it 'serves it, because a pinned version cannot grow after save' do
        definition = response.payload[:item][:sub_items].first[:definition]

        expect(definition[:prompt].bytesize).to eq(200.kilobytes)
      end
    end

    it 'loads items, versions, projects and root ancestors without a query per dependency' do
      allow(Ability).to receive(:allowed?).and_return(true)
      # A restricted agent compares root ancestors, which a public one skips. A project in a
      # subgroup has to look its root up, where a project under the top-level group does not.
      add_restricted_dependency('3.0.0')

      control = ActiveRecord::QueryRecorder.new { described_class.new(workflow: workflow, current_user: user).execute }

      add_restricted_dependency('4.0.0')

      expect { described_class.new(workflow: workflow, current_user: user).execute }
        .not_to exceed_query_limit(control)
    end

    def add_restricted_dependency(version)
      subgroup_project = create(:project, group: create(:group, parent: group))
      restricted_agent = create(:ai_catalog_agent, :restricted, project: subgroup_project)
      create(:ai_catalog_item_version_dependency,
        ai_catalog_item_version: item_version,
        dependency: restricted_agent,
        dependency_version: create(:ai_catalog_agent_version, :released, item: restricted_agent, version: version))
    end
  end
end
