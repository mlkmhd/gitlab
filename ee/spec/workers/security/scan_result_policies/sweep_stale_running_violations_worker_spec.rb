# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Security::ScanResultPolicies::SweepStaleRunningViolationsWorker, :clean_gitlab_redis_shared_state,
  feature_category: :security_policy_management do
  let_it_be(:project) { create(:project, :repository) }
  let_it_be_with_reload(:open_merge_request) do
    create(:merge_request, source_project: project, source_branch: 'feature', target_branch: 'master')
  end

  let_it_be_with_reload(:head_pipeline) do
    create(:ci_pipeline, :success, project: project, ref: open_merge_request.source_branch,
      sha: open_merge_request.diff_head_sha, head_pipeline_of: open_merge_request)
  end

  let_it_be(:merged_merge_request) { create(:merge_request, :merged, source_project: project, source_branch: 'fix') }
  let_it_be(:closed_merge_request) do
    create(:merge_request, :closed, source_project: project, source_branch: 'markdown')
  end

  let(:feature_licensed) { true }
  let(:timeout_worker) { Security::ScanResultPolicies::UnblockPendingMergeRequestViolationsWorker }

  before do
    stub_licensed_features(security_orchestration_policies: feature_licensed)
  end

  subject(:perform) { described_class.new.perform }

  def create_violation(merge_request, updated_at: 2.hours.ago)
    create(:scan_result_policy_violation, :running, project: project, merge_request: merge_request,
      updated_at: updated_at)
  end

  it_behaves_like 'an idempotent worker'

  context 'with an open merge request whose head pipeline finished' do
    before do
      create_violation(open_merge_request)
    end

    it 'schedules the policy evaluation timeout for that merge request', :aggregate_failures do
      expect(timeout_worker).to receive(:perform_async)
        .with(head_pipeline.id, { 'merge_request_id' => open_merge_request.id })
      expect(Gitlab::AppJsonLogger).to receive(:info).with(hash_including(
        event: 'sweep_stale_running_violations',
        merge_request_id: open_merge_request.id,
        Labkit::Fields::GL_PIPELINE_ID => head_pipeline.id))

      perform
    end

    context 'when the head pipeline is still running' do
      before do
        head_pipeline.update!(status: :running)
      end

      it 'does not schedule the timeout' do
        expect(timeout_worker).not_to receive(:perform_async)

        perform
      end
    end

    context 'when the merge request has no head pipeline' do
      before do
        open_merge_request.update!(head_pipeline: nil)
      end

      it 'does not schedule the timeout' do
        expect(timeout_worker).not_to receive(:perform_async)

        perform
      end
    end
  end

  context 'with merged and closed merge requests' do
    let!(:violations) { [create_violation(merged_merge_request), create_violation(closed_merge_request)] }

    it 'deletes their violations' do
      expect { perform }.to change { Security::ScanResultPolicyViolation.id_in(violations).count }.from(2).to(0)
    end
  end

  context 'with several stale violations in one project' do
    before do
      create_violation(merged_merge_request)
      create_violation(closed_merge_request)
    end

    it 'checks the feature flag once for the project' do
      allow(Feature).to receive(:enabled?).and_call_original
      expect(Feature).to receive(:enabled?).with(:sweep_stale_running_policy_violations, anything).once

      perform
    end
  end

  context 'when policies are not available for the project' do
    let!(:violations) { [create_violation(open_merge_request), create_violation(merged_merge_request)] }

    let(:feature_licensed) { false }

    it 'neither schedules a timeout nor deletes violations', :aggregate_failures do
      expect(timeout_worker).not_to receive(:perform_async)

      expect { perform }.not_to change { Security::ScanResultPolicyViolation.id_in(violations).count }
    end
  end

  context 'with a merge request that is being merged' do
    let_it_be(:locked_merge_request) do
      create(:merge_request, :locked, source_project: project, source_branch: 'wip')
    end

    let!(:violation) { create_violation(locked_merge_request) }

    it 'leaves it alone', :aggregate_failures do
      expect(timeout_worker).not_to receive(:perform_async)

      expect { perform }.not_to change { Security::ScanResultPolicyViolation.id_in(violation).count }
    end
  end

  context 'when the violations were updated recently' do
    let!(:violation) { create_violation(closed_merge_request, updated_at: 30.minutes.ago) }

    it 'leaves them alone', :aggregate_failures do
      expect(timeout_worker).not_to receive(:perform_async)

      expect { perform }.not_to change { Security::ScanResultPolicyViolation.id_in(violation).count }
    end
  end

  context 'when the violation is no longer running' do
    let!(:violation) do
      create(:scan_result_policy_violation, :failed, project: project, merge_request: closed_merge_request,
        updated_at: 2.hours.ago)
    end

    it 'leaves it alone' do
      expect { perform }.not_to change { Security::ScanResultPolicyViolation.id_in(violation).count }
    end
  end

  context 'when the feature flag is disabled for the project' do
    let!(:violation) { create_violation(closed_merge_request) }

    before do
      create_violation(open_merge_request)
      stub_feature_flags(sweep_stale_running_policy_violations: false)
    end

    it 'leaves the violations alone', :aggregate_failures do
      expect(timeout_worker).not_to receive(:perform_async)

      expect { perform }.not_to change { Security::ScanResultPolicyViolation.id_in(violation).count }
    end
  end

  context 'when more rows are stale than a run may scan' do
    let!(:older) { create_violation(closed_merge_request, updated_at: 3.hours.ago) }
    let!(:newer) { create_violation(merged_merge_request, updated_at: 2.hours.ago) }

    before do
      stub_const("#{described_class}::MAX_ROWS_PER_RUN", 1)
      stub_const("#{described_class}::BATCH_SIZE", 1)
    end

    it 'stops at the cap and resumes after the last scanned row on the next run', :aggregate_failures do
      described_class.new.perform

      expect(Security::ScanResultPolicyViolation.id_in([older, newer])).to contain_exactly(newer)

      described_class.new.perform

      expect(Security::ScanResultPolicyViolation.id_in([older, newer])).to be_empty
    end

    context 'when the scanned rows are left running' do
      let_it_be(:other_merge_request) { create(:merge_request, :closed) }

      let!(:skipped) do
        create(:scan_result_policy_violation, :running, project: other_merge_request.target_project,
          merge_request: other_merge_request, updated_at: 4.hours.ago)
      end

      before do
        stub_feature_flags(sweep_stale_running_policy_violations: project)
      end

      it 'resumes after them on the next run' do
        2.times { described_class.new.perform }

        expect(Security::ScanResultPolicyViolation.id_in([skipped, older, newer])).to contain_exactly(skipped, newer)
      end
    end
  end
end
