# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Gitlab::Duo::RiskAssessment::MarkFailedService, feature_category: :dap_code_review do
  let_it_be(:merge_request) { create(:merge_request) }

  let(:assessment_status) { :queued }
  let!(:assessment) { create(:merge_requests_risk_assessment, assessment_status, merge_request: merge_request) }
  let(:guard) { ->(record) { record.queued? } }

  subject(:execute) do
    described_class.new(
      assessment,
      guard: guard,
      log_message: 'Assessment gave up',
      log_context: { workflow_id: 42 }
    ).execute
  end

  it 'fails the assessment' do
    expect(execute).to be_success
    expect(assessment.reload).to be_failed
  end

  it 'logs why the assessment failed' do
    expect(Gitlab::AppLogger).to receive(:warn).with(
      message: 'Assessment gave up',
      merge_request_id: merge_request.id,
      workflow_id: 42
    )

    execute
  end

  it 'checks the guard against the locked row, not a stale copy' do
    stale = described_class.new(
      MergeRequests::RiskAssessment.find(assessment.id),
      guard: guard,
      log_message: 'Assessment gave up'
    )
    MergeRequests::RiskAssessment.find(assessment.id).mark_failed

    expect(stale.execute).to be_error
  end

  context 'when the guard refuses' do
    let(:assessment_status) { :scoring }

    it 'leaves the assessment as it is and does not log', :aggregate_failures do
      expect(Gitlab::AppLogger).not_to receive(:warn)

      expect(execute).to be_error
      expect(assessment.reload).to be_scoring
    end
  end
end
