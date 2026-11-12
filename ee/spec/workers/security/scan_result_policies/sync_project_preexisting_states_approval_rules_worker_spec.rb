# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Security::ScanResultPolicies::SyncProjectPreexistingStatesApprovalRulesWorker, feature_category: :security_policy_management do
  let_it_be(:project) { create(:project, :repository) }
  let(:per_mr_worker) { Security::ScanResultPolicies::SyncPreexistingStatesApprovalRulesWorker }
  let(:newly_detected_worker) { Security::ScanResultPolicies::SyncMergeRequestApprovalsWorker }
  let_it_be(:head_pipeline) do
    create(:ci_pipeline, :success, project: project, ref: 'feature', sha: project.commit('feature').sha,
      finished_at: Time.current)
  end

  let_it_be(:open_mr_with_rule) do
    create(:merge_request, source_project: project, source_branch: 'feature', target_branch: 'master',
      head_pipeline: head_pipeline)
  end

  let_it_be(:open_mr_without_rule) do
    create(:merge_request, source_project: project, source_branch: 'feature-b', target_branch: 'master')
  end

  let_it_be(:open_mr_with_rule_but_passing) do
    create(:merge_request, source_project: project, source_branch: 'feature-d', target_branch: 'master',
      head_pipeline: head_pipeline)
  end

  let_it_be(:open_mr_with_rule_warn_violation) do
    create(:merge_request, source_project: project, source_branch: 'feature-e', target_branch: 'master',
      head_pipeline: head_pipeline)
  end

  let_it_be(:open_mr_with_license_rule_failed_violation) do
    create(:merge_request, source_project: project, source_branch: 'feature-f', target_branch: 'master',
      head_pipeline: head_pipeline)
  end

  let_it_be(:open_mr_with_preexisting_rule_failed_violation) do
    create(:merge_request, source_project: project, source_branch: 'feature-g', target_branch: 'master',
      head_pipeline: head_pipeline)
  end

  let_it_be(:open_mr_with_preexisting_rule_failed_and_newly_detected_rule_passing) do
    create(:merge_request, source_project: project, source_branch: 'feature-h', target_branch: 'master',
      head_pipeline: head_pipeline)
  end

  let_it_be(:closed_mr_with_rule) do
    create(:merge_request, :closed, source_project: project, source_branch: 'feature-c', target_branch: 'master')
  end

  let_it_be(:other_project_mr_with_rule) { create(:merge_request) }

  let_it_be(:scan_finding_approval_policy_rule) { create(:approval_policy_rule, :scan_finding) }
  let_it_be(:preexisting_approval_policy_rule) { create(:approval_policy_rule, :scan_finding) }
  let_it_be(:license_finding_approval_policy_rule) { create(:approval_policy_rule, :license_finding) }

  before_all do
    create(:security_policy_project_link, project: project)

    [open_mr_with_rule, open_mr_with_rule_but_passing, open_mr_with_rule_warn_violation,
      open_mr_with_preexisting_rule_failed_and_newly_detected_rule_passing].each do |merge_request|
      create(:report_approver_rule, :scan_finding, merge_request: merge_request,
        vulnerability_states: %w[new_needs_triage], approval_policy_rule: scan_finding_approval_policy_rule)
    end

    [open_mr_with_preexisting_rule_failed_violation,
      open_mr_with_preexisting_rule_failed_and_newly_detected_rule_passing].each do |merge_request|
      create(:report_approver_rule, :scan_finding, merge_request: merge_request,
        vulnerability_states: %w[detected], approval_policy_rule: preexisting_approval_policy_rule)
      create(:scan_result_policy_violation, :previous_scan_finding, uuids: [SecureRandom.uuid],
        project: project, merge_request: merge_request,
        approval_policy_rule: preexisting_approval_policy_rule, status: :failed)
    end

    create(:report_approver_rule, :scan_finding, merge_request: open_mr_with_license_rule_failed_violation,
      vulnerability_states: %w[new_needs_triage], approval_policy_rule: scan_finding_approval_policy_rule)
    create(:report_approver_rule, :scan_finding, merge_request: closed_mr_with_rule)
    create(:report_approver_rule, :scan_finding, merge_request: other_project_mr_with_rule)

    create(:scan_result_policy_violation, :new_scan_finding, uuids: [SecureRandom.uuid],
      project: project, merge_request: open_mr_with_rule,
      approval_policy_rule: scan_finding_approval_policy_rule, status: :failed)
    create(:scan_result_policy_violation, :new_scan_finding, uuids: [SecureRandom.uuid],
      project: project, merge_request: open_mr_with_rule_warn_violation,
      approval_policy_rule: scan_finding_approval_policy_rule, status: :warn)
    create(:scan_result_policy_violation, :license_scanning,
      project: project, merge_request: open_mr_with_license_rule_failed_violation,
      approval_policy_rule: license_finding_approval_policy_rule, status: :failed)
  end

  describe '#perform' do
    subject(:run_worker) { described_class.new.perform(project_id) }

    before do
      allow(per_mr_worker).to receive(:perform_async)
    end

    let(:project_id) { project.id }

    it 'enqueues the per-merge-request worker for open MRs in the project with scan_finding rules' do
      expect(per_mr_worker).to receive(:perform_async).with(open_mr_with_rule.id).once

      run_worker
    end

    it 'does not enqueue for MRs without applicable rules, closed MRs, or MRs in other projects' do
      run_worker

      expect(per_mr_worker).not_to have_received(:perform_async).with(open_mr_without_rule.id)
      expect(per_mr_worker).not_to have_received(:perform_async).with(closed_mr_with_rule.id)
      expect(per_mr_worker).not_to have_received(:perform_async).with(other_project_mr_with_rule.id)
    end

    it 'enqueues the newly-detected states sync for open MRs with scan_finding rules against their head pipeline' do
      expect(newly_detected_worker).to receive(:perform_async)
        .with(head_pipeline.id, open_mr_with_rule.id).once

      run_worker
    end

    context 'when the merge request has no failed violation' do
      it 'does not enqueue the newly-detected states sync but still enqueues the pre-existing states sync' do
        allow(newly_detected_worker).to receive(:perform_async)

        expect(per_mr_worker).to receive(:perform_async).with(open_mr_with_rule_but_passing.id)

        run_worker

        expect(newly_detected_worker).not_to have_received(:perform_async)
          .with(anything, open_mr_with_rule_but_passing.id)
      end
    end

    context 'when a merge request with the same head pipeline setup has a failed violation' do
      before do
        create(:scan_result_policy_violation, :new_scan_finding, uuids: [SecureRandom.uuid],
          project: project, merge_request: open_mr_with_rule_but_passing,
          approval_policy_rule: scan_finding_approval_policy_rule, status: :failed)
      end

      it 'enqueues the newly-detected states sync, so the "does not enqueue" examples exercise the filter' do
        allow(newly_detected_worker).to receive(:perform_async)

        run_worker

        expect(newly_detected_worker).to have_received(:perform_async)
          .with(head_pipeline.id, open_mr_with_rule_but_passing.id)
      end
    end

    context 'when the merge request has only a warn scan_finding violation' do
      it 'does not enqueue the newly-detected states sync but still enqueues the pre-existing states sync' do
        allow(newly_detected_worker).to receive(:perform_async)

        expect(per_mr_worker).to receive(:perform_async).with(open_mr_with_rule_warn_violation.id)

        run_worker

        expect(newly_detected_worker).not_to have_received(:perform_async)
          .with(anything, open_mr_with_rule_warn_violation.id)
      end
    end

    context 'when the merge request has a failed violation only on a license_finding rule' do
      it 'does not enqueue the newly-detected states sync but still enqueues the pre-existing states sync' do
        allow(newly_detected_worker).to receive(:perform_async)

        expect(per_mr_worker).to receive(:perform_async).with(open_mr_with_license_rule_failed_violation.id)

        run_worker

        expect(newly_detected_worker).not_to have_received(:perform_async)
          .with(anything, open_mr_with_license_rule_failed_violation.id)
      end
    end

    context 'when the merge request has a failed violation only on a pre-existing-state rule' do
      it 'does not enqueue the newly-detected states sync but still enqueues the pre-existing states sync' do
        allow(newly_detected_worker).to receive(:perform_async)

        expect(per_mr_worker).to receive(:perform_async).with(open_mr_with_preexisting_rule_failed_violation.id)

        run_worker

        expect(newly_detected_worker).not_to have_received(:perform_async)
          .with(anything, open_mr_with_preexisting_rule_failed_violation.id)
      end
    end

    context 'when a pre-existing-state rule failed and a newly-detected rule is passing' do
      it 'does not re-evaluate the passing newly-detected rule' do
        allow(newly_detected_worker).to receive(:perform_async)

        run_worker

        expect(newly_detected_worker).not_to have_received(:perform_async)
          .with(anything, open_mr_with_preexisting_rule_failed_and_newly_detected_rule_passing.id)
      end
    end

    context 'when the failed newly-detected rule has only the default vulnerability states' do
      where(:states) { [[[]], [%w[new_needs_triage new_dismissed]], [%w[new_dismissed new_needs_triage]]] }

      with_them do
        before do
          ApprovalMergeRequestRule.where(merge_request: open_mr_with_rule).update_all(vulnerability_states: states)
        end

        it 'does not enqueue the newly-detected states sync but still enqueues the pre-existing states sync' do
          expect(per_mr_worker).to receive(:perform_async).with(open_mr_with_rule.id)
          expect(newly_detected_worker).not_to receive(:perform_async)

          run_worker
        end
      end
    end

    context 'when the failed newly-detected rule has the default states plus a pre-existing state' do
      before do
        ApprovalMergeRequestRule.where(merge_request: open_mr_with_rule)
          .update_all(vulnerability_states: %w[new_needs_triage new_dismissed detected])
      end

      it 'enqueues the newly-detected states sync' do
        expect(newly_detected_worker).to receive(:perform_async).with(head_pipeline.id, open_mr_with_rule.id)

        run_worker
      end
    end

    context 'when the newly-detected rule has a skipped violation' do
      before do
        Security::ScanResultPolicyViolation.where(merge_request: open_mr_with_rule).update_all(status: :skipped)
      end

      it 'does not enqueue the newly-detected states sync but still enqueues the pre-existing states sync' do
        allow(newly_detected_worker).to receive(:perform_async)

        expect(per_mr_worker).to receive(:perform_async).with(open_mr_with_rule.id)

        run_worker

        expect(newly_detected_worker).not_to have_received(:perform_async).with(anything, open_mr_with_rule.id)
      end
    end

    context 'when the merge request has no pipeline for its diff head' do
      before do
        MergeRequest.id_in(open_mr_with_rule.id).update_all(head_pipeline_id: nil)
      end

      it 'does not enqueue the newly-detected states sync but still enqueues the pre-existing states sync' do
        expect(per_mr_worker).to receive(:perform_async).with(open_mr_with_rule.id)
        expect(newly_detected_worker).not_to receive(:perform_async)

        run_worker
      end
    end

    context 'when the head pipeline is still running' do
      before do
        Ci::Pipeline.id_in(head_pipeline.id).update_all(status: 'running')
      end

      it 'does not enqueue the newly-detected states sync but still enqueues the pre-existing states sync' do
        expect(per_mr_worker).to receive(:perform_async).with(open_mr_with_rule.id)
        expect(newly_detected_worker).not_to receive(:perform_async)

        run_worker
      end
    end

    context 'when the head pipeline reports are still being ingested' do
      shared_examples 'skips the newly-detected states sync' do
        it 'does not enqueue the newly-detected states sync but still enqueues the pre-existing states sync' do
          expect(per_mr_worker).to receive(:perform_async).with(open_mr_with_rule.id)
          expect(newly_detected_worker).not_to receive(:perform_async)

          run_worker
        end
      end

      context 'when no scan is stored yet' do
        before do
          build = create(:ee_ci_build, :success, pipeline: head_pipeline, project: project)
          create(:ee_ci_job_artifact, :sast, job: build, project: project)
        end

        it_behaves_like 'skips the newly-detected states sync'
      end

      context 'when a scan is processing' do
        before do
          create(:security_scan, latest: true, status: :created, pipeline: head_pipeline, project: project)
        end

        it_behaves_like 'skips the newly-detected states sync'

        context 'when the head pipeline is blocked on a manual job' do
          before do
            Ci::Pipeline.id_in(head_pipeline.id).update_all(status: 'manual', finished_at: nil)
          end

          it_behaves_like 'skips the newly-detected states sync'
        end

        context 'when the head pipeline finished longer ago than the ingestion wait' do
          let(:max_wait) { Security::ScanResultPolicies::UnblockPendingMergeRequestViolationsWorker::MAX_INGESTION_WAIT }

          before do
            Ci::Pipeline.id_in(head_pipeline.id).update_all(finished_at: (max_wait + 1.minute).ago)
          end

          it 'enqueues the newly-detected states sync' do
            expect(newly_detected_worker).to receive(:perform_async).with(head_pipeline.id, open_mr_with_rule.id)

            run_worker
          end
        end
      end
    end

    context 'when the head pipeline reports are ingested' do
      before do
        create(:security_scan, :latest_successful, pipeline: head_pipeline, project: project)
      end

      it 'enqueues the newly-detected states sync' do
        expect(newly_detected_worker).to receive(:perform_async).with(head_pipeline.id, open_mr_with_rule.id)

        run_worker
      end
    end

    context 'when the project does not exist' do
      let(:project_id) { non_existing_record_id }

      it 'does nothing' do
        expect(per_mr_worker).not_to receive(:perform_async)

        run_worker
      end
    end

    context 'when the project has no approval policy' do
      let_it_be(:project_without_policy) { create(:project) }
      let_it_be(:mr_with_rule) do
        create(:merge_request, source_project: project_without_policy, source_branch: 'x', target_branch: 'master')
      end

      let(:project_id) { project_without_policy.id }

      before_all do
        create(:report_approver_rule, :scan_finding, merge_request: mr_with_rule)
      end

      it 'returns early without enqueueing per-merge-request workers' do
        expect(per_mr_worker).not_to receive(:perform_async)

        run_worker
      end
    end

    it_behaves_like 'an idempotent worker' do
      let(:job_args) { [project.id] }
    end
  end
end
