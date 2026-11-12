# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Ai::Catalog::FoundationalFlow::RiskClassification::OnSessionEnded, feature_category: :dap_code_review do
  let_it_be_with_reload(:merge_request) { create(:merge_request) }
  let_it_be(:flow_reference) { Ai::Catalog::FoundationalFlow.risk_classification_v1.reference }

  let(:status) { :failed }
  let(:assessment_status) { :queued }
  let(:workflow) { create_session(status) }

  let!(:assessment) { create(:merge_requests_risk_assessment, assessment_status, merge_request: merge_request) }

  subject(:call) { described_class.call(workflow: workflow) }

  def create_session(status, **attributes)
    create(:duo_workflows_workflow, status,
      project: merge_request.target_project,
      merge_request: merge_request,
      workflow_definition: flow_reference, **attributes)
  end

  shared_examples 'leaves the assessment as it is' do
    it 'leaves the assessment as it is' do
      expect { call }.not_to change { assessment.reload.status_name }
    end
  end

  %i[finished failed stopped].each do |ending|
    context "when a #{ending} session never submitted a result" do
      let(:status) { ending }

      it 'fails the assessment' do
        call

        expect(assessment.reload).to be_failed
      end

      it 'logs why the assessment failed' do
        expect(Gitlab::AppLogger).to receive(:warn).with(
          message: 'Risk classification session ended without a result',
          merge_request_id: merge_request.id,
          workflow_id: workflow.id,
          workflow_status: ending.to_s
        )

        call
      end
    end
  end

  context 'when the session submitted a result that is still being scored' do
    let(:assessment_status) { :scoring }

    it_behaves_like 'leaves the assessment as it is'
  end

  context 'when the assessment already completed' do
    let(:assessment_status) { :complete }

    it_behaves_like 'leaves the assessment as it is'

    it 'does not log' do
      expect(Gitlab::AppLogger).not_to receive(:warn)

      call
    end
  end

  context 'when a newer session is still live' do
    before do
      workflow
      create_session(:running)
    end

    it_behaves_like 'leaves the assessment as it is'
  end

  context 'when a newer background session is still live' do
    before do
      workflow
      create_session(:running, execution_mode: :background)
    end

    it_behaves_like 'leaves the assessment as it is'
  end

  context 'when an older session that queued the assessment is still running' do
    before do
      create_session(:running)
      workflow
    end

    it_behaves_like 'leaves the assessment as it is'
  end

  context 'when a newer session was just created' do
    before do
      workflow
      create_session(:created)
    end

    it_behaves_like 'leaves the assessment as it is'
  end

  %i[paused input_required plan_approval_required tool_call_approval_required idle].each do |parked|
    context "when the only other session is #{parked}" do
      before do
        create(:duo_workflows_workflow,
          project: merge_request.target_project,
          merge_request: merge_request,
          workflow_definition: flow_reference,
          status: Ai::DuoWorkflows::Workflow.state_machines[:status].states[parked].value)
        workflow
      end

      it 'fails the assessment' do
        call

        expect(assessment.reload).to be_failed
      end
    end
  end

  context 'when every other session has also ended' do
    before do
      create_session(:stopped)
      workflow
      create_session(:failed)
    end

    it 'fails the assessment' do
      call

      expect(assessment.reload).to be_failed
    end
  end

  context 'when a submission moves the assessment to scoring before the lock is taken' do
    # Reloaded so the hook finds the assessment itself, instead of the cached factory instance.
    let(:workflow) { create_session(status).reload }

    before do
      allow_next_found_instance_of(MergeRequests::RiskAssessment) do |instance|
        allow(instance).to receive(:with_lock).and_wrap_original do |original, *args, &block|
          scoring = MergeRequests::RiskAssessment.state_machines[:status].states[:scoring].value
          MergeRequests::RiskAssessment.find(instance.id).update_column(:status, scoring)
          original.call(*args, &block)
        end
      end
    end

    it 'leaves the submitted assessment as it is' do
      call

      expect(assessment.reload).to be_scoring
    end
  end

  context 'when the only newer session belongs to another flow' do
    before do
      workflow
      create_session(:running, workflow_definition: 'code_review/v1')
    end

    it 'still fails the assessment, since another flow never queues it' do
      call

      expect(assessment.reload).to be_failed
    end
  end

  context 'when the only newer session ran on the client' do
    before do
      workflow
      create_session(:running, execution_mode: :client)
    end

    it 'still fails the assessment, since a client session never queues it' do
      call

      expect(assessment.reload).to be_failed
    end
  end

  context 'when the session was retried and is running again' do
    let(:status) { :running }

    it_behaves_like 'leaves the assessment as it is'
  end

  context 'when the merge request has no assessment' do
    let!(:assessment) { nil }

    it 'does nothing' do
      expect(Gitlab::AppLogger).not_to receive(:warn)

      expect { call }.not_to raise_error
    end
  end

  context 'when the session has no merge request' do
    let(:workflow) { build_stubbed(:duo_workflows_workflow, :failed) }

    it_behaves_like 'leaves the assessment as it is'
  end
end
