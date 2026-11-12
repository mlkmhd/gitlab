# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Security::SecurityOrchestrationPolicies::ResyncProjectPoliciesService,
  feature_category: :security_policy_management do
  describe 'resync of linked, out-of-scope and disabled policies' do
    let_it_be_with_reload(:project) { create(:project) }
    let_it_be(:configuration) { create(:security_orchestration_policy_configuration, project: project) }
    let_it_be_with_reload(:in_scope_policy) do
      create(:security_policy, :require_approval, security_orchestration_policy_configuration: configuration)
    end

    let_it_be_with_reload(:out_of_scope_policy) do
      create(:security_policy, :require_approval,
        security_orchestration_policy_configuration: configuration, policy_index: 1)
    end

    let_it_be_with_reload(:disabled_policy) do
      create(:security_policy, :require_approval,
        security_orchestration_policy_configuration: configuration, policy_index: 2)
    end

    let_it_be(:merge_request) { create(:merge_request, source_project: project) }

    subject(:resync) { described_class.new(project: project, configuration: configuration).execute }

    before_all do
      [in_scope_policy, out_of_scope_policy, disabled_policy].each do |policy|
        create(:approval_policy_rule, security_policy: policy)
      end
    end

    before do
      Security::SecurityOrchestrationPolicies::LinkPolicyConfigurationService
        .new(project: project, configuration: configuration).execute
      [in_scope_policy, out_of_scope_policy, disabled_policy].each do |policy|
        create(:approval_merge_request_rule,
          approval_project_rule: project_rules(policy).first,
          merge_request: merge_request,
          security_orchestration_policy_configuration: configuration,
          approval_policy_rule: policy.approval_policy_rules.first)
      end

      out_of_scope_policy.update!(scope: { projects: { excluding: [{ id: project.id }] } })
      disabled_policy.update!(enabled: false)
    end

    def project_rules(policy)
      project.approval_rules.for_approval_policy_rules(policy.approval_policy_rules)
    end

    def merge_request_rules(policy)
      merge_request.approval_rules.for_approval_policy_rules(policy.approval_policy_rules)
    end

    it 'rebuilds stale rules of an unchanged policy', :aggregate_failures do
      stale_rule = project_rules(in_scope_policy).first
      stale_rule.update!(approvals_required: 5)

      resync

      rebuilt_rule = project_rules(in_scope_policy).sole
      expect(rebuilt_rule.id).not_to eq(stale_rule.id)
      expect(rebuilt_rule.approvals_required).to eq(1)
      expect(in_scope_policy.linked_to_project?(project)).to be(true)
    end

    it 'cleans up out-of-scope and disabled policies', :aggregate_failures do
      expect(merge_request_rules(out_of_scope_policy)).to exist
      expect(merge_request_rules(disabled_policy)).to exist

      resync

      [out_of_scope_policy, disabled_policy].each do |policy|
        expect(policy.linked_to_project?(project)).to be(false)
        expect(project_rules(policy)).to be_empty
        expect(merge_request_rules(policy)).to be_empty
      end
    end

    it 'blocks merging until the deferred sweep re-applies the rebuilt rules', :aggregate_failures,
      :clean_gitlab_redis_shared_state do
      stub_licensed_features(security_orchestration_policies: true)
      create(:protected_branch, project: project, name: merge_request.target_branch)

      expect(merge_request.missing_policy_approval_rules?).to be(false)

      resync

      merge_request.reload
      expect(merge_request.missing_policy_approval_rules?).to be(true)
      expect(MergeRequests::Mergeability::CheckSecurityPolicyViolationsService
        .new(merge_request: merge_request, params: {}).execute.status)
        .to eq(Gitlab::MergeRequests::Mergeability::CheckResult::CHECKING_STATUS)
    end

    it 'defers the merge request sweep of relinked policies to one job for the project', :aggregate_failures do
      allow(Security::SecurityOrchestrationPolicies::SyncMergeRequestsService).to receive(:new).and_call_original
      expect(Security::ScanResultPolicies::SyncMergeRequestsForProjectWorker)
        .to receive(:perform_async).with(project.id, configuration.id).once

      resync

      # Unlinking already deletes the merge request rules, so no policy sweeps inline
      expect(Security::SecurityOrchestrationPolicies::SyncMergeRequestsService).not_to have_received(:new)
    end

    context 'when resyncing one policy fails' do
      def resync_payload(policy)
        { event: { event_type: 'Security::PolicyResyncEvent', data: { security_policy_id: policy.id } } }
      end

      def fail_resync_of(policy, error)
        allow(Security::SecurityOrchestrationPolicies::SyncPolicyEventService).to receive(:new).and_call_original
        allow(Security::SecurityOrchestrationPolicies::SyncPolicyEventService)
          .to receive(:new).with(hash_including(security_policy: policy)).and_wrap_original do |method, **args|
            method.call(**args).tap do |service|
              allow(service).to receive(:execute).and_raise(error)
            end
          end
      end

      before do
        allow(Gitlab::ErrorTracking).to receive(:track_exception)
      end

      shared_examples 'hands the failed policy to the per-policy worker' do
        before do
          fail_resync_of(in_scope_policy, error)
        end

        it 'tracks the error, retries the policy separately and still resyncs the others', :aggregate_failures do
          expect(Security::SyncProjectPolicyWorker)
            .to receive(:perform_in)
            .with(1.minute, project.id, in_scope_policy.id, {}, resync_payload(in_scope_policy)).once
          # The failed policy sweeps inline in its own job, and no other approval policy was relinked here
          expect(Security::ScanResultPolicies::SyncMergeRequestsForProjectWorker).not_to receive(:perform_async)

          expect { resync }.not_to raise_error

          expect(Gitlab::ErrorTracking).to have_received(:track_exception).with(
            instance_of(error_class), security_policy_id: in_scope_policy.id, project_id: project.id
          )
          expect(out_of_scope_policy.linked_to_project?(project)).to be(false)
          expect(disabled_policy.linked_to_project?(project)).to be(false)
        end
      end

      context 'with ActiveRecord::RecordInvalid' do
        let(:error) { ActiveRecord::RecordInvalid }
        let(:error_class) { ActiveRecord::RecordInvalid }

        it_behaves_like 'hands the failed policy to the per-policy worker'
      end

      context 'with an unexpected error' do
        let(:error) { StandardError.new('boom') }
        let(:error_class) { StandardError }

        it_behaves_like 'hands the failed policy to the per-policy worker'
      end

      context 'when the failed policy is not the one that was relinked' do
        before do
          fail_resync_of(out_of_scope_policy, StandardError.new('boom'))
        end

        it 'still schedules one sweep for the relinked policy', :aggregate_failures do
          expect(Security::SyncProjectPolicyWorker)
            .to receive(:perform_in)
            .with(1.minute, project.id, out_of_scope_policy.id, {}, resync_payload(out_of_scope_policy)).once
          expect(Security::ScanResultPolicies::SyncMergeRequestsForProjectWorker)
            .to receive(:perform_async).with(project.id, configuration.id).once

          resync

          expect(in_scope_policy.linked_to_project?(project)).to be(true)
          expect(disabled_policy.linked_to_project?(project)).to be(false)
        end
      end
    end

    context 'when no approval policy needs a sweep' do
      before do
        [in_scope_policy, out_of_scope_policy, disabled_policy].each do |policy|
          policy.unlink_project!(project)
          policy.delete_approval_policy_rules_for_project(project, policy.approval_policy_rules)
        end

        in_scope_policy.update!(enabled: false)
      end

      it 'does not enqueue SyncMergeRequestsForProjectWorker' do
        expect(Security::ScanResultPolicies::SyncMergeRequestsForProjectWorker).not_to receive(:perform_async)

        resync
      end
    end
  end

  describe 'resync of schedule-based policies' do
    let_it_be(:project) { create(:project) }
    let_it_be(:configuration) { create(:security_orchestration_policy_configuration, project: project) }
    let_it_be(:scan_execution_policy) do
      create(:security_policy, :scan_execution_policy, security_orchestration_policy_configuration: configuration)
    end

    let_it_be(:schedule_policy) do
      create(:security_policy, :pipeline_execution_schedule_policy,
        security_orchestration_policy_configuration: configuration)
    end

    let_it_be_with_reload(:disabled_scan_execution_policy) do
      create(:security_policy, :scan_execution_policy,
        security_orchestration_policy_configuration: configuration, policy_index: 1, enabled: false)
    end

    let_it_be_with_reload(:disabled_schedule_policy) do
      create(:security_policy, :pipeline_execution_schedule_policy,
        security_orchestration_policy_configuration: configuration, policy_index: 1, enabled: false)
    end

    subject(:resync) { described_class.new(project: project, configuration: configuration).execute }

    before do
      disabled_scan_execution_policy.link_project!(project)
      create(:security_scan_execution_project_schedule,
        project: project, security_policy: disabled_scan_execution_policy)
      disabled_schedule_policy.link_project!(project)
      create(:security_pipeline_execution_project_schedule,
        project: project, security_policy: disabled_schedule_policy)
    end

    it 'recreates the project schedules of enabled policies', :aggregate_failures do
      expect_next_instance_of(
        Security::SecurityOrchestrationPolicies::ScanExecutionPolicies::CreateProjectSchedulesService,
        project: project, security_policy: scan_execution_policy
      ) { |service| expect(service).to receive(:execute) }
      expect_next_instance_of(
        Security::SecurityOrchestrationPolicies::PipelineExecutionPolicies::CreateProjectSchedulesService,
        project: project, security_policy: schedule_policy
      ) { |service| expect(service).to receive(:execute) }

      resync

      expect(scan_execution_policy.linked_to_project?(project)).to be(true)
      expect(schedule_policy.linked_to_project?(project)).to be(true)
    end

    it 'cleans up disabled linked policies and their project schedules', :aggregate_failures do
      allow(Security::PipelineExecutionPolicies::CancelPolicyPipelinesWorker).to receive(:perform_async)

      resync

      expect(Security::PipelineExecutionPolicies::CancelPolicyPipelinesWorker)
        .to have_received(:perform_async).with(disabled_schedule_policy.id, project.id)

      expect(disabled_scan_execution_policy.linked_to_project?(project)).to be(false)
      expect(disabled_scan_execution_policy.scan_execution_project_schedules.for_project(project)).to be_empty
      expect(disabled_schedule_policy.linked_to_project?(project)).to be(false)
      expect(disabled_schedule_policy.security_pipeline_execution_project_schedules.for_project(project)).to be_empty
    end

    it 'does not schedule a merge request sweep' do
      create(:merge_request, source_project: project)

      expect(Security::ScanResultPolicies::SyncMergeRequestsForProjectWorker).not_to receive(:perform_async)

      resync
    end
  end
end
