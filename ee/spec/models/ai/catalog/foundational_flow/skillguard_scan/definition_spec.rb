# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Ai::Catalog::FoundationalFlow::SkillguardScan::Definition, feature_category: :duo_agent_platform do
  using RSpec::Parameterized::TableSyntax

  subject(:flow) { Ai::Catalog::FoundationalFlow.skillguard_scan_v1 }

  it 'resolves against the v1 Flow Registry tier' do
    expect(flow.foundational_flow_reference).to eq('skillguard_scan/v1')
  end

  it 'is an experimental feature', :aggregate_failures do
    expect(flow.feature_maturity).to eq('experimental')
    expect(flow.display_name).to eq('SkillGuard Security Scan')
  end

  it 'is gated by the skillguard_scan_flow feature flag' do
    expect(flow.feature_flag).to eq('skillguard_scan_flow')
  end

  it 'runs in the ambient environment' do
    expect(flow.environment).to eq('ambient')
  end

  it 'is Ultimate only' do
    expect(flow.ultimate_only).to be true
  end

  it 'creates and supports only the pipeline_hooks trigger', :aggregate_failures do
    expected = [::Ai::FlowTrigger::EVENT_TYPES[:pipeline_hooks]]

    expect(flow.triggers).to match_array(expected)
    expect(flow.supported_events).to match_array(expected)
  end

  it 'declares the SAST report artifact so the workload job uploads it' do
    expect(flow.report_artifacts.stringify_keys).to eq('sast' => ['gl-sast-report.json'])
  end

  it 'checks triggered runs against the SkillGuard scan profile' do
    expect(flow.run_eligibility_resolver).to eq(Ai::Catalog::FoundationalFlow::SkillguardScan::RunEligibility)
  end

  describe 'which pipeline_hooks fire the flow' do
    # The auto-created trigger carries the default trigger filter, and the real
    # Ai::FlowTriggers::FilterEvaluator ANDs it with the flow's precondition.
    # pipeline_hooks fires on every status transition and for every pipeline, so
    # only a successful default-branch pipeline must start a scan.
    let(:flow_trigger) do
      build(:ai_flow_trigger, filter: flow.default_trigger_filter).tap do |trigger|
        allow(trigger).to receive(:foundational_flow).and_return(flow)
      end
    end

    where(:status, :default_branch, :fires) do
      'success'  | true  | true
      'success'  | false | false
      'failed'   | true  | false
      'running'  | true  | false
      'canceled' | true  | false
    end

    with_them do
      it 'fires only on a successful default-branch pipeline' do
        evaluator = ::Ai::FlowTriggers::FilterEvaluator.new(
          flow_trigger: flow_trigger, hook_scope: :pipeline_hooks,
          data: { object_attributes: { status: status, default_branch: default_branch } }
        )

        expect(evaluator.allowed?).to be(fires)
      end
    end
  end
end
