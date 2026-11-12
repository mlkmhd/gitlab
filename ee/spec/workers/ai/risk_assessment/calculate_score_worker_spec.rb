# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Ai::RiskAssessment::CalculateScoreWorker, feature_category: :dap_code_review do
  let_it_be_with_reload(:merge_request) { create(:merge_request) }

  let(:diff_sha) { merge_request.diff_head_sha }
  let(:classification) do
    {
      'claims' => {
        'authorization' => { 'value' => 'true', 'evidence' => 'app/policies/project_policy.rb:42' },
        'api_contract' => { 'value' => 'false' }
      },
      'summary' => 'Adds a session token refresh path.'
    }
  end

  let(:workflow) do
    create(:duo_workflows_workflow, project: merge_request.target_project,
      user: merge_request.author, merge_request: merge_request)
  end

  let(:assessment_status) { :scoring }
  let!(:assessment) do
    create(:merge_requests_risk_assessment, assessment_status, merge_request: merge_request, diff_sha: diff_sha)
  end

  subject(:perform) { described_class.new.perform(merge_request.id, diff_sha, classification, workflow.id) }

  context 'when assessment is scoring' do
    before do
      perform
      assessment.reload
    end

    it 'updates the assessment score and metadata', :aggregate_failures do
      expect(assessment).to be_complete
      expect(assessment.score).to be_between(0, 100)
      expect(assessment.confidence).to be_between(0, 100)
      expect(assessment.scoring_function_version).to eq('v1')
      expect(assessment.assessed_at).to be_present
      expect(assessment.classification).to eq(classification)
      expect(assessment.rationale).to eq('Adds a session token refresh path.')
      expect(assessment.duo_workflow_id).to eq(workflow.id)
      expect(assessment.diff_sha).to eq(diff_sha)
      expect(assessment.missing_signals).to be_present
      expect(assessment.signal_breakdown.pluck('signal')).to include('authorization')
    end
  end

  context 'when the assessment is no longer scoring' do
    before do
      assessment.mark_failed
    end

    it 'leaves the row as it stands rather than half-applying a score' do
      perform

      expect(assessment.reload).to be_failed
      expect(assessment.score).to be_nil
    end

    it 'logs the discarded score, so a result that arrived too late is visible' do
      expect(Gitlab::AppLogger).to receive(:warn).with(
        hash_including(
          message: 'Risk assessment score arrived for an assessment that is not waiting on this revision',
          merge_request_id: merge_request.id,
          status: :failed,
          incoming_diff_sha: diff_sha,
          assessment_diff_sha: diff_sha
        )
      )

      perform
    end
  end

  context 'when the merge request does not exist' do
    it 'does not raise errors' do
      expect do
        described_class.new.perform(non_existing_record_id, diff_sha, classification, workflow.id)
      end.not_to raise_error
    end
  end

  context 'when the assessment does not exist' do
    it 'does not raise errors' do
      assessment.destroy!

      expect { perform }.not_to raise_error
    end
  end

  it 'does not complete an assessment that failed elsewhere while this worker is deciding' do
    # Simulates a session hook failing the row in between this worker's initial
    # (unlocked) read and the row lock #perform now takes before acting.
    allow_next_found_instance_of(MergeRequests::RiskAssessment) do |instance|
      allow(instance).to receive(:with_lock).and_wrap_original do |original, *args, &block|
        MergeRequests::RiskAssessment.find(assessment.id).mark_failed
        original.call(*args, &block)
      end
    end

    perform

    expect(assessment.reload).to be_failed
    expect(assessment.score).to be_nil
  end

  it_behaves_like 'an idempotent worker' do
    let(:job_args) { [merge_request.id, diff_sha, classification, workflow.id] }
  end

  it 'gives up after a few retries, so a failing job fails the assessment within minutes' do
    expect(described_class.get_sidekiq_options['retry']).to eq(3)
  end

  context 'when the assessment is still queued, as web nodes from before the scoring status leave it' do
    let(:assessment_status) { :queued }

    it 'scores and completes it' do
      perform

      expect(assessment.reload).to be_complete
      expect(assessment.score).to be_present
    end
  end

  context 'when jobs from overlapping submissions finish out of order' do
    let!(:earlier_diff) { create(:merge_request_diff, merge_request: merge_request) }
    let!(:later_diff) { create(:merge_request_diff, merge_request: merge_request) }

    def perform_for(diff, summary: 'Adds a session token refresh path.')
      described_class.new.perform(merge_request.id, diff.head_commit_sha, classification.merge('summary' => summary),
        workflow.id)
    end

    it 'keeps the later revision when the earlier job runs after it completed' do
      perform_for(later_diff)

      expect { perform_for(earlier_diff) }.not_to change { assessment.reload.attributes }
      expect(assessment).to be_complete
    end

    it 'replaces the earlier revision when the later job runs after it completed', :aggregate_failures do
      perform_for(earlier_diff, summary: 'Earlier revision.')
      perform_for(later_diff, summary: 'Later revision.')

      expect(assessment.reload).to be_complete
      expect(assessment.diff_sha).to eq(later_diff.head_commit_sha)
      expect(assessment.rationale).to eq('Later revision.')
    end

    it 'does not write an earlier revision to a queued row that holds a later one' do
      perform_for(later_diff)
      assessment.reload.enqueue

      expect { perform_for(earlier_diff) }.not_to change { assessment.reload.attributes }
    end

    it 'does not write an earlier revision to a row scoring a later one' do
      perform_for(later_diff)
      allow(described_class).to receive(:perform_async)
      assessment.reload.refresh(later_diff.head_commit_sha, classification, workflow.id)

      perform_for(earlier_diff)

      expect(assessment.reload).to be_scoring
      expect(assessment.diff_sha).to eq(later_diff.head_commit_sha)
    end

    it 'does not rescore a completed row for the revision it already holds' do
      perform_for(later_diff)

      expect { perform_for(later_diff) }.not_to change { assessment.reload.assessed_at }
    end
  end

  describe '.sidekiq_retries_exhausted' do
    let(:job_created_at) { 1.minute.from_now }
    let(:job) do
      { 'args' => [merge_request.id, diff_sha, classification, workflow.id], 'created_at' => job_created_at.to_f }
    end

    subject(:exhaust) { described_class.sidekiq_retries_exhausted_block.call(job, StandardError.new) }

    it 'fails the assessment, so it does not stay scoring' do
      exhaust

      expect(assessment.reload).to be_failed
    end

    it 'logs why the assessment failed' do
      expect(Gitlab::AppLogger).to receive(:warn).with(
        message: 'Risk classification scoring gave up after its retries',
        merge_request_id: merge_request.id
      )

      exhaust
    end

    %i[queued complete failed].each do |state|
      context "when the assessment is #{state}" do
        let(:assessment_status) { state }

        it 'leaves it alone, since this job no longer owns it' do
          expect(Gitlab::AppLogger).not_to receive(:warn)

          exhaust

          expect(assessment.reload.status_name).to eq(state)
        end
      end
    end

    context 'when a newer submission refreshed the assessment after this job was created' do
      let(:job_created_at) { 1.minute.ago }

      it 'leaves it to the newer submission\'s job' do
        expect(Gitlab::AppLogger).not_to receive(:warn)

        exhaust

        expect(assessment.reload).to be_scoring
      end
    end

    it 'does nothing when the merge request has no assessment' do
      assessment.destroy!

      expect(Gitlab::AppLogger).not_to receive(:warn)
      expect { exhaust }.not_to raise_error
    end

    it 'does nothing when the merge request is gone' do
      job['args'][0] = non_existing_record_id

      expect(Gitlab::AppLogger).not_to receive(:warn)
      expect { exhaust }.not_to raise_error
    end
  end

  describe 'domain tags' do
    it 'tags only the domains a claim answered positively' do
      perform

      expect(assessment.reload.domain_tags).to contain_exactly('authorization')
    end

    it 'tags nothing when no domain was touched' do
      described_class.new.perform(
        merge_request.id, diff_sha,
        { 'claims' => { 'authorization' => { 'value' => 'false' } }, 'summary' => 'Typo fix.' },
        workflow.id
      )

      expect(assessment.reload.domain_tags).to be_empty
    end
  end
end
