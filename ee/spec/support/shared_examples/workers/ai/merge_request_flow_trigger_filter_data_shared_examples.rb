# frozen_string_literal: true

# Runs the real FilterEvaluator on the filter key of the worker's event type, for a worker that includes
# Ai::MergeRequestFlowTriggerFilterData. Needs `service_account` (the service account of the flow trigger) and
# `event_for` (a lambda that builds the worker's cloud event for a merge request).
RSpec.shared_examples 'a merge request flow trigger worker with scope filters' do
  using RSpec::Parameterized::TableSyntax

  describe '#handle_event' do
    # Separate project so the unfiltered `flow_trigger` of the worker spec does not also fire.
    let_it_be(:scope_project) { create(:project) }
    let_it_be(:flow_merge_request) { create(:merge_request, source_project: scope_project, source_branch: 'flow') }
    let_it_be(:flow_draft_merge_request) do
      create(:merge_request, :draft_merge_request, source_project: scope_project, source_branch: 'flow-draft')
    end

    let_it_be(:human_merge_request) { create(:merge_request, source_project: scope_project, source_branch: 'human') }
    let_it_be(:human_draft_merge_request) do
      create(:merge_request, :draft_merge_request, source_project: scope_project, source_branch: 'human-draft')
    end

    let(:run_service) { instance_double(Ai::FlowTriggers::RunService, execute: nil) }

    before_all do
      [flow_merge_request, flow_draft_merge_request].each do |merge_request|
        create(:duo_workflows_workflow_merge_request,
          workflow: create(:duo_workflows_workflow, project: scope_project),
          merge_request: merge_request, project: scope_project, link_type: :created)
      end
    end

    before do
      create(:ai_flow_trigger,
        project: scope_project,
        user: service_account,
        event_types: [Ai::FlowTrigger::EVENT_TYPES[described_class.event_type]],
        filter: {
          described_class.event_type.to_s => {
            'rules' => [
              { 'field' => 'created_by_flow', 'operator' => 'in', 'value' => [created_by_flow] },
              { 'field' => 'draft', 'operator' => 'in', 'value' => [draft] }
            ]
          }
        })

      allow(Ai::FlowTriggers::RunService).to receive(:new).and_return(run_service)
    end

    where(:created_by_flow, :draft, :event_merge_request, :flow_runs) do
      true  | false | ref(:flow_merge_request)        | 1
      true  | false | ref(:flow_draft_merge_request)  | 0
      true  | false | ref(:human_merge_request)       | 0
      true  | false | ref(:human_draft_merge_request) | 0
      false | true  | ref(:flow_merge_request)        | 0
      false | true  | ref(:flow_draft_merge_request)  | 0
      false | true  | ref(:human_merge_request)       | 0
      false | true  | ref(:human_draft_merge_request) | 1
    end

    with_them do
      it 'starts a flow only on the merge requests that match the rules' do
        expect(run_service).to receive(:execute).exactly(flow_runs).times

        described_class.new.handle_event(event_for.call(event_merge_request))
      end
    end
  end
end
