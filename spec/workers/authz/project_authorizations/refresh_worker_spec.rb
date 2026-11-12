# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Authz::ProjectAuthorizations::RefreshWorker, feature_category: :permissions do
  let(:worker) { described_class.new }

  describe 'database health deferral' do
    before do
      stub_feature_flags(defer_primary_auth_refresh_on_wal_rate: false)
    end

    it 'is on without a feature flag, and never on autovacuum' do
      expect(described_class.defer_on_database_health_signal?).to be(true)
      expect(described_class.database_health_check_attrs).to include(
        gitlab_schema: :gitlab_main_org, delay_by: 1.minute,
        indicators: Gitlab::Database::HealthStatus::GLOBAL_INDICATORS
      )
      expect(described_class.database_health_check_attrs[:indicators])
        .not_to include(Gitlab::Database::HealthStatus::Indicators::AutovacuumActiveOnTable)
    end
  end

  it 'runs at most one job per slot' do
    expect(described_class.get_concurrency_limit).to eq(described_class::SLOTS)
  end

  it 'never overlaps a slot with itself, and reruns it once a cron run skipped it' do
    expect(described_class.get_deduplicate_strategy).to eq(:until_executed)
    expect(described_class.get_deduplication_options).to include(if_deduplicated: :reschedule_once)
  end

  describe '#perform' do
    context 'for the cron run' do
      it 'queues one job per slot' do
        expect(described_class).to receive(:bulk_perform_async).with([[1], [2], [3], [4]])

        worker.perform
      end
    end

    context 'for a slot' do
      let(:dropped_counts) { { 'user' => 1 } }
      let(:expanded_counts) { { 'namespace_subtree' => 1 } }

      def expect_service(poll_interval:, drained:)
        expect_next_instance_of(Authz::ProjectAuthorizations::RefreshService,
          an_instance_of(Gitlab::Metrics::RuntimeLimiter), poll_interval: poll_interval) do |service|
          expect(service).to receive(:execute).and_return(ServiceResponse.success(
            payload: { drained: drained, dropped_counts: dropped_counts, expanded_counts: expanded_counts }))
        end
      end

      it 'polls in the polling slot until its runtime limit, and logs the counts' do
        expect_service(poll_interval: described_class::POLL_INTERVAL, drained: false)

        expect(worker).to receive(:log_extra_metadata_on_done).with(:drained, false)
        expect(worker).to receive(:log_extra_metadata_on_done).with(:dropped_counts, dropped_counts)
        expect(worker).to receive(:log_extra_metadata_on_done).with(:expanded_counts, expanded_counts)

        worker.perform(described_class::POLLING_SLOT)
      end

      it 'stops at an empty queue in the other slots, and logs the counts' do
        expect_service(poll_interval: nil, drained: true)

        expect(worker).to receive(:log_extra_metadata_on_done).with(:drained, true)
        expect(worker).to receive(:log_extra_metadata_on_done).with(:dropped_counts, dropped_counts)
        expect(worker).to receive(:log_extra_metadata_on_done).with(:expanded_counts, expanded_counts)

        worker.perform(2)
      end

      it 'gives the service the job runtime limit' do
        expect(Gitlab::Metrics::RuntimeLimiter).to receive(:new).with(described_class::MAX_RUNTIME).and_call_original
        allow_next_instance_of(Authz::ProjectAuthorizations::RefreshService) do |service|
          allow(service).to receive(:execute).and_return(ServiceResponse.success(payload: {}))
        end

        worker.perform(1)
      end
    end
  end
end
