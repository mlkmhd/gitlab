# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Security::SyncPolicyConfigurationWorker, feature_category: :security_policy_management do
  let_it_be(:group) { create(:group) }
  let(:event) do
    Security::PolicyConfigurationAssignedEvent.build(configuration: configuration)
  end

  let_it_be(:project) { create(:project, group: group) }
  let_it_be(:configuration) do
    create(:security_orchestration_policy_configuration, project: project)
  end

  subject(:use_event) { consume_event(subscriber: described_class, event: event) }

  it_behaves_like 'subscribes to event'

  it_behaves_like 'worker with data consistency', described_class, data_consistency: :sticky

  it 'has the `until_executed` deduplicate strategy' do
    expect(described_class.get_deduplicate_strategy).to eq(:until_executed)
  end

  describe '.idempotency_arguments' do
    it 'returns the event type and the configuration_id from the event data' do
      expect(described_class.idempotency_arguments([event.class.name, event.data]))
        .to eq([event.class.name, configuration.id])
    end
  end

  describe 'deduplication', :clean_gitlab_redis_queues_metadata do
    def enqueue(event)
      described_class.perform_async(event.class.name, event.data_hash)
    end

    it 'keeps an assignment and a resync of the same configuration apart' do
      enqueue(event)
      enqueue(Security::PolicyConfigurationResyncEvent.build(configuration: configuration))
      enqueue(Security::PolicyConfigurationResyncEvent.build(configuration: configuration))

      expect(described_class.jobs.map { |job| job['args'].first }).to eq(
        %w[Security::PolicyConfigurationAssignedEvent Security::PolicyConfigurationResyncEvent]
      )
    end
  end

  context 'when the event is a resync' do
    let_it_be(:approval_policy) do
      create(:security_policy, :require_approval, security_orchestration_policy_configuration: configuration)
    end

    let_it_be(:disabled_policy) do
      create(:security_policy, :require_approval, security_orchestration_policy_configuration: configuration,
        policy_index: 1, enabled: false)
    end

    let(:event) { Security::PolicyConfigurationResyncEvent.build(configuration: configuration) }

    it_behaves_like 'subscribes to event'

    it 'enqueues SyncProjectPoliciesWorker with the force_resync reason' do
      expect(Security::SyncProjectPoliciesWorker).to receive(:bulk_perform_in_with_contexts)
        .with(
          described_class::BATCH_DELAY_INTERVAL,
          [project.id],
          arguments_proc: satisfy { |proc|
            proc.call(project.id) == [
              project.id, configuration.id, Security::SecurityOrchestrationPolicies::SyncReason.to_params(:force_resync)
            ]
          },
          context_proc: satisfy { |proc| proc.call(nil) == { project: project } }
        )

      use_event
    end

    it 'syncs the compliance frameworks of each enabled policy once' do
      expect(Security::SecurityOrchestrationPolicies::ComplianceFrameworks::SyncService)
        .to receive(:new).with(security_policy: approval_policy, policy_diff: nil).once.and_call_original
      expect(Security::SecurityOrchestrationPolicies::ComplianceFrameworks::SyncService)
        .not_to receive(:new).with(security_policy: disabled_policy, policy_diff: nil)

      use_event
    end

    context 'with soft-deleted policies' do
      let_it_be(:deleted_policy) do
        create(:security_policy, :require_approval, security_orchestration_policy_configuration: configuration,
          policy_index: -1, enabled: false)
      end

      let_it_be(:other_configuration_deleted_policy) do
        create(:security_policy, :require_approval, policy_index: -1, enabled: false)
      end

      it 'enqueues the deletion of the configuration\'s deleted policies only' do
        expect(Security::DeleteSecurityPolicyWorker).to receive(:perform_async).with(deleted_policy.id).once
        expect(Security::DeleteSecurityPolicyWorker).not_to receive(:perform_async).with(approval_policy.id)
        expect(Security::DeleteSecurityPolicyWorker)
          .not_to receive(:perform_async).with(other_configuration_deleted_policy.id)

        use_event
      end

      context 'when there are more deleted policies than the limit' do
        let_it_be(:second_deleted_policy) do
          create(:security_policy, :require_approval, security_orchestration_policy_configuration: configuration,
            policy_index: -2, enabled: false)
        end

        before do
          stub_const("#{described_class}::DELETED_POLICIES_LIMIT", 1)
        end

        it 'enqueues the deletion of at most the limit' do
          expect(Security::DeleteSecurityPolicyWorker).to receive(:perform_async).once

          use_event
        end
      end

      context 'when the event is a configuration assignment' do
        let(:event) { Security::PolicyConfigurationAssignedEvent.build(configuration: configuration) }

        it 'does not enqueue any deletion' do
          expect(Security::DeleteSecurityPolicyWorker).not_to receive(:perform_async)

          use_event
        end
      end
    end

    context 'with a pipeline execution policy' do
      let_it_be(:config_project) { create(:project) }
      let_it_be(:pipeline_execution_policy) do
        create(:security_policy, :pipeline_execution_policy,
          security_orchestration_policy_configuration: configuration, policy_index: 2)
      end

      before_all do
        create(:security_pipeline_execution_policy_config_link,
          project: config_project, security_policy: pipeline_execution_policy)
      end

      before do
        allow_next_found_instance_of(Security::OrchestrationPolicyConfiguration) do |found_configuration|
          allow(found_configuration).to receive(:policy_last_updated_by).and_return(nil)
        end
      end

      it 'syncs the pipeline execution policy metadata' do
        expect(Security::SyncPipelineExecutionPolicyMetadataWorker).to receive(:perform_async)
          .with(config_project.id, nil, pipeline_execution_policy.content['content'], [pipeline_execution_policy.id])

        use_event
      end

      it 'loads the config links with one query however many pipeline execution policies there are' do
        link_query_count = -> do
          ActiveRecord::QueryRecorder.new { consume_event(subscriber: described_class, event: event) }.log
            .count { |sql| sql.include?('FROM "security_pipeline_execution_policy_config_links"') }
        end

        expect(link_query_count.call).to eq(1)

        [3, 4].each do |index|
          policy = create(:security_policy, :pipeline_execution_policy,
            security_orchestration_policy_configuration: configuration, policy_index: index)
          create(:security_pipeline_execution_policy_config_link, project: config_project, security_policy: policy)
        end

        expect(link_query_count.call).to eq(1)
      end
    end
  end

  context 'when configuration does not exist' do
    let(:event) do
      stub_configuration = instance_double(Security::OrchestrationPolicyConfiguration, id: non_existing_record_id)
      Security::PolicyConfigurationAssignedEvent.build(configuration: stub_configuration)
    end

    it 'does not enqueue SyncProjectPoliciesWorker' do
      expect(Security::SyncProjectPoliciesWorker).not_to receive(:bulk_perform_in_with_contexts)

      use_event
    end
  end

  context 'when configuration has no projects' do
    it 'does not enqueue SyncProjectPoliciesWorker' do
      allow_next_found_instance_of(Security::OrchestrationPolicyConfiguration) do |config|
        allow(config).to receive(:all_project_ids).and_yield([])
      end

      expect(Security::SyncProjectPoliciesWorker).not_to receive(:bulk_perform_in_with_contexts)

      use_event
    end
  end

  context 'when configuration is project-based' do
    it 'enqueues SyncProjectPoliciesWorker with a 1-interval delay' do
      expect(Security::SyncProjectPoliciesWorker).to receive(:bulk_perform_in_with_contexts)
        .with(
          described_class::BATCH_DELAY_INTERVAL,
          [project.id],
          arguments_proc: satisfy { |proc|
            proc.call(project.id) == [
              project.id, configuration.id, { 'sync_reason' => 'configuration_assigned', 'triggered_by_assign' => true }
            ]
          },
          context_proc: satisfy { |proc| proc.call(nil) == { project: project } }
        )

      use_event
    end
  end

  context 'when configuration is namespace-based' do
    let_it_be(:configuration) do
      create(:security_orchestration_policy_configuration, namespace: group, project: nil)
    end

    let_it_be(:another_project) { create(:project, group: group) }

    it 'enqueues SyncProjectPoliciesWorker for all group projects with namespace context and params' do
      expect(Security::SyncProjectPoliciesWorker).to receive(:bulk_perform_in_with_contexts)
        .with(
          described_class::BATCH_DELAY_INTERVAL,
          contain_exactly(project.id, another_project.id),
          arguments_proc: satisfy { |proc|
            proc.call(project.id) == [
              project.id, configuration.id, { 'sync_reason' => 'configuration_assigned', 'triggered_by_assign' => true }
            ]
          },
          context_proc: satisfy { |proc| proc.call(nil) == { namespace: group } }
        )

      use_event
    end

    it 'uses strictly increasing delays across batches' do
      batch1 = [1, 2, 3]
      batch2 = [4, 5, 6]
      received_delays = []

      allow_next_found_instance_of(Security::OrchestrationPolicyConfiguration) do |config|
        allow(config).to receive(:all_project_ids).and_yield(batch1).and_yield(batch2)
      end

      allow(Security::SyncProjectPoliciesWorker).to receive(:bulk_perform_in_with_contexts) do |delay, *|
        received_delays << delay
      end

      use_event

      expect(received_delays).to eq([
        1 * described_class::BATCH_DELAY_INTERVAL,
        2 * described_class::BATCH_DELAY_INTERVAL
      ])
    end
  end
end
