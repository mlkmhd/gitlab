# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Ai::Catalog::FoundationalFlow::Workplan::Definition, feature_category: :duo_agent_platform do
  subject(:flow) { Ai::Catalog::FoundationalFlow.workplan_v1 }

  it 'returns the workplan foundational flow', :aggregate_failures do
    expect(flow.foundational_flow_reference).to eq('workplan/v1')
    expect(flow.display_name).to eq('Generate Workplan')
    expect(flow.feature_maturity).to eq('experimental')
    expect(flow.environment).to eq('web')
    expect(flow.goal_templates).to eq(::Ai::Catalog::GoalTemplates::Workplan)
    expect(flow.noteable_resolver).to be_present
  end

  it 'is gated by the workplan feature flag' do
    expect(flow.feature_flag).to eq('workplan')
  end

  it 'has no default triggers and supports mention, assign and work item events', :aggregate_failures do
    expect(flow.triggers).to be_empty
    expect(flow.supported_events).to eq(
      Ai::FlowTrigger::EVENT_TYPES.values_at(:mention, :assign, :work_item)
    )
  end

  describe '#supports_resource?' do
    let_it_be(:project) { create(:project) }

    it 'supports issues and work items', :aggregate_failures do
      expect(flow.supported_resource_types).to eq([::Issue])
      expect(flow.supports_resource?(build_stubbed(:issue, project: project))).to be(true)
      expect(flow.supports_resource?(build_stubbed(:work_item, project: project))).to be(true)
    end

    it 'rejects merge requests and a missing resource', :aggregate_failures do
      expect(flow.supports_resource?(build_stubbed(:merge_request, source_project: project))).to be(false)
      expect(flow.supports_resource?(nil)).to be(false)
    end
  end

  describe '#resolve_flow_version_for' do
    using RSpec::Parameterized::TableSyntax

    let_it_be(:group) { create(:group) }
    let_it_be(:project) { create(:project, group: group) }
    let_it_be(:user) { create(:user) }

    subject(:resolved) { flow.resolve_flow_version_for(container: project, user: user) }

    where(:workplan_score_actor, :software_factory_actor, :version) do
      ref(:user)  | ref(:project) | '1.3.0'
      ref(:user)  | ref(:group)   | '1.3.0'
      ref(:user)  | false         | '1.1.0'
      ref(:group) | ref(:project) | '1.0.0'
      false       | ref(:project) | '1.0.0'
      false       | false         | '1.0.0'
    end

    with_them do
      before do
        stub_feature_flags(workplan_score: workplan_score_actor, dap_software_factory: software_factory_actor)
      end

      it 'resolves the workplan version' do
        expect(resolved).to eq(flow_config_id: 'workplan', flow_config_schema_version: 'v1', flow_version: version)
      end
    end

    context 'when there is no container' do
      subject(:resolved) { flow.resolve_flow_version_for(container: nil, user: user) }

      before do
        stub_feature_flags(workplan_score: user)
      end

      it 'resolves workplan 1.1.0' do
        expect(resolved).to eq(flow_config_id: 'workplan', flow_config_schema_version: 'v1', flow_version: '1.1.0')
      end
    end

    context 'when there is no user' do
      subject(:resolved) { flow.resolve_flow_version_for(container: project, user: nil) }

      before do
        stub_feature_flags(workplan_score: user)
      end

      it 'resolves workplan 1.0.0' do
        expect(resolved).to eq(flow_config_id: 'workplan', flow_config_schema_version: 'v1', flow_version: '1.0.0')
      end
    end
  end

  describe '#resolve_noteable_for' do
    let_it_be(:project) { create(:project) }
    let_it_be(:work_item) { create(:work_item, project: project) }

    it 'returns the work item matching the URL embedded in the goal' do
      goal = "Plan this: #{Gitlab::UrlBuilder.build(work_item)} thanks"

      expect(flow.resolve_noteable_for(project: project, goal: goal)).to eq(work_item)
    end

    it 'resolves the legacy issues URL form' do
      goal = "See https://gitlab.com/#{project.full_path}/-/issues/#{work_item.iid}"

      expect(flow.resolve_noteable_for(project: project, goal: goal)).to eq(work_item)
    end

    it 'returns nil for a malformed goal' do
      expect(flow.resolve_noteable_for(project: project, goal: 'not-a-url')).to be_nil
    end

    it 'returns nil for a nil goal' do
      expect(flow.resolve_noteable_for(project: project, goal: nil)).to be_nil
    end
  end
end
