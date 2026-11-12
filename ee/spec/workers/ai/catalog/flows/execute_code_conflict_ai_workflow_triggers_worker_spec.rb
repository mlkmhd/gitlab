# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Ai::Catalog::Flows::ExecuteCodeConflictAiWorkflowTriggersWorker,
  feature_category: :dap_triggers do
  let_it_be(:user) { create(:user) }
  # In a group, for the catalog consumer of the Duo Developer flow trigger.
  let_it_be(:project) { create(:project, :in_group) }
  let_it_be(:merge_request) do
    create(:merge_request, source_project: project, target_project: project, author: user)
  end

  let_it_be(:service_account) { create(:service_account) }
  let_it_be(:flow_trigger) do
    create(:ai_flow_trigger,
      project: project,
      user: service_account,
      event_types: [Ai::FlowTrigger::EVENT_TYPES[:merge_request_code_conflict]]
    )
  end

  let(:cloud_event) { MergeRequests::CodeConflictEvent.build(merge_request: merge_request) }
  let(:resource) { merge_request }
  let(:event) { cloud_event }

  let(:wrong_event) do
    MergeRequests::DraftStateChangeEvent.new(
      data: { current_user_id: user.id, merge_request_id: merge_request.id }
    )
  end

  let(:doomed_resource) do
    create(:merge_request, source_project: project, target_project: project, author: user, source_branch: 'doomed')
  end

  let(:doomed_resource_event) { MergeRequests::CodeConflictEvent.build(merge_request: doomed_resource) }

  it_behaves_like 'subscribes to event'
  it_behaves_like 'a cloud events flow trigger worker' do
    # Ai::MergeRequestFlowTriggerFilterData adds the merge request fields.
    let(:filter_data) { { 'created_by_flow' => false, 'draft' => false } }
  end

  it_behaves_like 'a merge request flow trigger worker with scope filters' do
    let(:event_for) { ->(merge_request) { MergeRequests::CodeConflictEvent.build(merge_request: merge_request) } }
  end

  # If the job inherits the link of a flow, RunService cannot link the same service account to the merge request
  # author. See https://gitlab.com/gitlab-org/gitlab/-/work_items/639574.
  describe 'composite identity of the enqueuing context', :request_store do
    let_it_be(:flow_service_account) { create(:user, :ai_service_account) }
    let_it_be(:other_user) { create(:user) }

    it 'opts out of the composite identity passthrough' do
      expect(described_class.skip_composite_identity_passthrough?).to be(true)
    end

    it 'does not give the link of a flow to the job of the conflict event' do
      # The link that a push of the flow makes in `/internal/allowed`.
      ::Gitlab::Auth::Identity.link_from_scoped_user(flow_service_account, other_user)

      expect { Gitlab::EventStore.publish(cloud_event) }.to change { described_class.jobs.size }.by(1)
      expect(described_class.jobs.last).not_to have_key(::Gitlab::Auth::Identity::COMPOSITE_IDENTITY_SIDEKIQ_ARG)
    end
  end

  describe '#handle_event' do
    subject(:handle_event) { worker.handle_event(cloud_event) }

    let_it_be(:developer_item) do
      create(:ai_catalog_item, :flow, :public, foundational_flow_reference: 'developer/v1')
    end

    let_it_be(:developer_trigger) do
      create(:ai_flow_trigger, :for_catalog_consumer,
        project: project,
        ai_catalog_item_consumer: create(:ai_catalog_item_consumer, :child_item_consumer,
          project: project, item: developer_item),
        event_types: [Ai::FlowTrigger::EVENT_TYPES[:merge_request_code_conflict]]
      )
    end

    # Another foundational flow from the catalog, so the check cannot match every catalog or foundational flow.
    let_it_be(:code_review_trigger) do
      create(:ai_flow_trigger, :for_catalog_consumer,
        project: project,
        ai_catalog_item_consumer: create(:ai_catalog_item_consumer, :child_item_consumer,
          project: project,
          item: create(:ai_catalog_item, :flow, :public, foundational_flow_reference: 'code_review/v1')),
        event_types: [Ai::FlowTrigger::EVENT_TYPES[:merge_request_code_conflict]]
      )
    end

    let(:worker) { described_class.new }
    let(:run_params) { { input: merge_request.iid.to_s, event: :merge_request_code_conflict } }
    let(:run_service) { instance_double(Ai::FlowTriggers::RunService, execute: ServiceResponse.success) }
    let(:developer_run_service) { instance_double(Ai::FlowTriggers::RunService, execute: ServiceResponse.success) }
    let(:code_review_run_service) { instance_double(Ai::FlowTriggers::RunService, execute: ServiceResponse.success) }

    before do
      allow(Ai::FlowTriggers::FilterEvaluator).to receive(:new)
        .and_return(instance_double(Ai::FlowTriggers::FilterEvaluator, allowed?: true))
      allow(Ai::FlowTriggers::RunService).to receive(:new).and_return(run_service)
      allow(Ai::FlowTriggers::RunService).to receive(:new)
        .with(hash_including(flow_trigger: developer_trigger)).and_return(developer_run_service)
      allow(Ai::FlowTriggers::RunService).to receive(:new)
        .with(hash_including(flow_trigger: code_review_trigger)).and_return(code_review_run_service)
      allow(worker.logger).to receive(:info)
    end

    shared_examples 'starts only the other flows' do |reason|
      it 'does not start Duo Developer and logs the reason', :aggregate_failures do
        expect(worker.logger).to receive(:info).with(hash_including(
          'message' => 'Duo Developer does not resolve conflicts on this merge request.',
          'reason' => reason,
          'flow_trigger_id' => developer_trigger.id,
          'merge_request_id' => merge_request.id
        ))
        expect(developer_run_service).not_to receive(:execute)
        expect(run_service).to receive(:execute).with(run_params)
        expect(code_review_run_service).to receive(:execute).with(run_params)

        handle_event
      end
    end

    it 'starts Duo Developer and the other flows', :aggregate_failures do
      expect(developer_run_service).to receive(:execute).with(run_params)
      expect(run_service).to receive(:execute).with(run_params)
      expect(code_review_run_service).to receive(:execute).with(run_params)

      handle_event
    end

    context 'when dap_software_factory is disabled' do
      before do
        stub_feature_flags(dap_software_factory: false)
      end

      it_behaves_like 'starts only the other flows', :software_factory_disabled
    end

    context 'when the merge request is no longer open' do
      where(:state) { %i[closed merged locked] }

      with_them do
        before do
          MergeRequest.find(merge_request.id).update_column(:state_id, MergeRequest.available_states[state])
        end

        it_behaves_like 'starts only the other flows', :not_open
      end
    end

    # The filter of the flow trigger holds the scope.
    context 'when the merge request is a draft that no flow created' do
      before do
        MergeRequest.find(merge_request.id).update!(title: "Draft: #{merge_request.title}")
      end

      it 'starts Duo Developer' do
        expect(developer_run_service).to receive(:execute).with(run_params)

        handle_event
      end
    end

    context 'when dap_software_factory is enabled for the project only' do
      before do
        stub_feature_flags(dap_software_factory: project)
      end

      it 'starts Duo Developer' do
        expect(developer_run_service).to receive(:execute).with(run_params)

        handle_event
      end
    end
  end
end
