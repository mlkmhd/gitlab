# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Security::SyncProjectPoliciesWorker, feature_category: :security_policy_management do
  let_it_be(:project) { create(:project) }
  let_it_be(:policy_configuration) { create(:security_orchestration_policy_configuration, project: project) }
  let_it_be(:security_policy) do
    create(:security_policy, security_orchestration_policy_configuration: policy_configuration)
  end

  let_it_be(:deleted_security_policy) do
    create(:security_policy, :deleted, security_orchestration_policy_configuration: policy_configuration)
  end

  let(:project_id) { project.id }
  let(:policy_configuration_id) { policy_configuration.id }

  it 'has until_executed deduplication with reschedule_once', :aggregate_failures do
    expect(described_class.get_deduplicate_strategy).to eq(:until_executed)
    expect(described_class.get_deduplication_options).to eq({ if_deduplicated: :reschedule_once })
  end

  describe 'deduplication', :clean_gitlab_redis_queues_metadata do
    let(:args) do
      [project_id, policy_configuration_id, Security::SecurityOrchestrationPolicies::SyncReason.to_params(:force_resync)]
    end

    def execute_first_job
      described_class.perform_async(*args)
      job = described_class.jobs.sole
      described_class.clear

      Gitlab::SidekiqMiddleware::DuplicateJobs::Server.new.call(described_class.new, job, job['queue']) { yield }
    end

    def rescheduled_jobs
      described_class.jobs.select { |job| job['rescheduled_once'] }
    end

    it 'reschedules a duplicate enqueued while a job executes instead of running both' do
      execute_first_job do
        described_class.perform_async(*args)

        expect(described_class.jobs).to be_empty
      end

      expect(rescheduled_jobs.map { |job| job['args'] }).to eq([args])
    end

    it 'reschedules a scheduled duplicate that becomes due while a job executes' do
      execute_first_job do
        described_class.perform_in(1.second, *args)
        scheduled_job = described_class.jobs.sole
        described_class.clear

        # Sidekiq's scheduler pushes the due job again, without `at`
        Sidekiq::Client.push(scheduled_job.except('at'))

        expect(described_class.jobs).to be_empty
      end

      expect(rescheduled_jobs.map { |job| job['args'] }).to eq([args])
    end
  end

  describe '#perform' do
    subject(:perform) { described_class.new.perform(project_id, policy_configuration_id) }

    context 'when project and policy configuration exist' do
      it 'calls SyncProjectPolicyWorker for each undeleted security policy' do
        expect(Security::SyncProjectPolicyWorker).to receive(:perform_async).with(
          project.id, security_policy.id, {}, {}
        ).once

        perform
      end

      context 'when sync_reason is force_resync' do
        subject(:perform) do
          described_class.new.perform(project_id, policy_configuration_id, { 'sync_reason' => 'force_resync' })
        end

        it 'resyncs all policies of the configuration in one job' do
          expect_next_instance_of(
            Security::SecurityOrchestrationPolicies::ResyncProjectPoliciesService,
            project: project,
            configuration: policy_configuration
          ) do |service|
            expect(service).to receive(:execute)
          end
          expect(Security::SyncProjectPolicyWorker).not_to receive(:perform_async)

          perform
        end

        context 'when feature flag state_based_security_policy_resync is disabled' do
          before do
            stub_feature_flags(state_based_security_policy_resync: false)
          end

          it 'calls SyncProjectPolicyWorker with resync event payload' do
            expect(Security::SecurityOrchestrationPolicies::ResyncProjectPoliciesService).not_to receive(:new)
            expect(Security::SyncProjectPolicyWorker).to receive(:perform_async).with(
              project.id, security_policy.id, {}, { event: {
                event_type: 'Security::PolicyResyncEvent',
                data: { security_policy_id: security_policy.id }
              } }
            ).once

            perform
          end
        end
      end

      context 'with the legacy force_resync param' do
        subject(:perform) do
          described_class.new.perform(project_id, policy_configuration_id, { 'force_resync' => true })
        end

        before do
          stub_feature_flags(state_based_security_policy_resync: false)
        end

        it 'calls SyncProjectPolicyWorker with resync event payload' do
          expect(Security::SyncProjectPolicyWorker).to receive(:perform_async).with(
            project.id, security_policy.id, {}, hash_including(event: hash_including(
              event_type: 'Security::PolicyResyncEvent'
            ))
          ).once

          perform
        end
      end

      context 'with the legacy triggered_by_assign param' do
        subject(:perform) do
          described_class.new.perform(project_id, policy_configuration_id, { 'triggered_by_assign' => true })
        end

        it 'calls LinkPolicyConfigurationService' do
          expect_next_instance_of(Security::SecurityOrchestrationPolicies::LinkPolicyConfigurationService) do |service|
            expect(service).to receive(:execute)
          end

          perform
        end
      end

      context 'when sync_reason is policy_change' do
        subject(:perform) do
          described_class.new.perform(project_id, policy_configuration_id, { 'sync_reason' => 'policy_change' })
        end

        it 'calls SyncProjectPolicyWorker with empty params' do
          expect(Security::SyncProjectPolicyWorker).to receive(:perform_async).with(
            project.id, security_policy.id, {}, {}
          ).once

          perform
        end
      end

      context 'when sync_reason is configuration_assigned' do
        subject(:perform) do
          described_class.new.perform(
            project_id, policy_configuration_id, { 'sync_reason' => 'configuration_assigned' }
          )
        end

        it 'calls LinkPolicyConfigurationService instead of SyncProjectPolicyWorker' do
          expect_next_instance_of(
            Security::SecurityOrchestrationPolicies::LinkPolicyConfigurationService,
            project: project,
            configuration: policy_configuration
          ) do |service|
            expect(service).to receive(:execute)
          end

          expect(Security::SyncProjectPolicyWorker).not_to receive(:perform_async)

          perform
        end
      end
    end

    context 'when project does not exist' do
      let(:project_id) { non_existing_record_id }

      it 'does not call SyncProjectPolicyWorker' do
        expect(Security::SyncProjectPolicyWorker).not_to receive(:perform_async)

        perform
      end
    end

    context 'when policy configuration does not exist' do
      let(:policy_configuration_id) { non_existing_record_id }

      it 'does not call SyncProjectPolicyWorker' do
        expect(Security::SyncProjectPolicyWorker).not_to receive(:perform_async)

        perform
      end
    end

    context 'when there are no security policies' do
      let_it_be(:policy_configuration) { create(:security_orchestration_policy_configuration) }

      it 'does not call SyncProjectPolicyWorker' do
        expect(Security::SyncProjectPolicyWorker).not_to receive(:perform_async)

        perform
      end
    end
  end
end
