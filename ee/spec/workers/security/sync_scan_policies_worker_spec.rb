# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Security::SyncScanPoliciesWorker, feature_category: :security_policy_management do
  describe '.perform_debounced', :clean_gitlab_redis_shared_state do
    let_it_be(:configuration) { create(:security_orchestration_policy_configuration) }
    let_it_be(:other_configuration) { create(:security_orchestration_policy_configuration) }

    it 'schedules one delayed sync per configuration for repeated calls', :aggregate_failures do
      expect(described_class).to receive(:perform_in).with(described_class::DEBOUNCE_DELAY, configuration.id).once
      expect(described_class).to receive(:perform_in).with(described_class::DEBOUNCE_DELAY, other_configuration.id)
      expect(described_class).not_to receive(:perform_async)

      3.times { described_class.perform_debounced(configuration) }
      described_class.perform_debounced(other_configuration)
    end

    it 'schedules again after the debounce window has passed' do
      expect(described_class).to receive(:perform_in).with(described_class::DEBOUNCE_DELAY, configuration.id).twice

      described_class.perform_debounced(configuration)
      Gitlab::ExclusiveLease.reset_all!
      described_class.perform_debounced(configuration)
    end

    it 'holds the lease for less than the delay so it expires before the scheduled job runs' do
      expect(Gitlab::ExclusiveLease).to receive(:throttle)
        .with(configuration.id, group: :security_policy_sync_debounce,
          period: a_value < described_class::DEBOUNCE_DELAY)

      described_class.perform_debounced(configuration)
    end

    context 'when the debounce_security_policy_sync feature flag is disabled' do
      before do
        stub_feature_flags(debounce_security_policy_sync: false)
      end

      it 'enqueues a sync for every call' do
        expect(described_class).to receive(:perform_async).with(configuration.id).twice
        expect(described_class).not_to receive(:perform_in)

        2.times { described_class.perform_debounced(configuration) }
      end
    end
  end

  describe '#perform' do
    let_it_be(:configuration) { create(:security_orchestration_policy_configuration, configured_at: nil) }

    subject(:worker) { described_class.new }

    include_examples 'an idempotent worker' do
      let(:job_args) { [configuration.id, { 'sync_reason' => 'policy_change' }] }
    end

    it 'has the `until_executed` deduplicate strategy' do
      expect(described_class.get_deduplicate_strategy).to eq(:until_executed)
    end

    it 'calls SyncPoliciesService' do
      expect_next_instance_of(
        Security::SecurityOrchestrationPolicies::SyncPoliciesService,
        configuration: configuration,
        params: {}
      ) do |service|
        expect(service).to receive(:execute)
      end

      worker.perform(configuration.id)
    end

    it 'does not call SyncPoliciesService when configuration is not present' do
      expect(Security::SecurityOrchestrationPolicies::SyncPoliciesService).not_to receive(:new)

      worker.perform(non_existing_record_id)
    end

    %w[force_resync configuration_assigned].each do |sync_reason|
      context "when sync_reason is #{sync_reason}" do
        it 'passes the sync_reason to SyncPoliciesService' do
          expect_next_instance_of(
            Security::SecurityOrchestrationPolicies::SyncPoliciesService,
            configuration: configuration,
            params: { sync_reason: sync_reason }
          ) do |service|
            expect(service).to receive(:execute)
          end

          worker.perform(configuration.id, { 'sync_reason' => sync_reason })
        end
      end
    end
  end
end
