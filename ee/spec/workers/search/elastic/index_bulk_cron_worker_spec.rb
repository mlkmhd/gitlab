# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Search::Elastic::IndexBulkCronWorker, feature_category: :global_search do
  include ExclusiveLeaseHelpers

  let(:worker) { described_class.new }
  let(:lease_key) { 'search/elastic/index_bulk_cron_worker' }

  let(:shards) { [0, 1] }
  let(:shard_number) { shards.first }
  let(:max_score) { 42 }

  before do
    stub_const("Elastic::ProcessBookkeepingService::SHARDS", shards)
    stub_ee_application_setting(elasticsearch_indexing: true, elasticsearch_requeue_workers: true)
    allow(Search::ClusterHealthCheck::Elastic).to receive(:healthy?).and_return(true)
    allow(::Elastic::ProcessBookkeepingService).to receive(:max_score).and_return(max_score)
  end

  describe '.perform' do
    it "queues all shards for execution with each shard's max score" do
      shards.each do |shard_number|
        expect(::Elastic::ProcessBookkeepingService).to receive(:max_score).with(shard_number).ordered
        expect(described_class).to receive(:perform_async).with(shard_number, max_score).ordered
      end

      worker.perform
    end

    context 'when search_elastic_bulk_index_replica_reads is disabled' do
      before do
        stub_feature_flags(search_elastic_bulk_index_replica_reads: false)
      end

      it 'queues all shards for execution without a max score' do
        expect(::Elastic::ProcessBookkeepingService).not_to receive(:max_score)

        shards.each do |shard_number|
          expect(described_class).to receive(:perform_async).with(shard_number)
        end

        worker.perform
      end
    end

    context 'when legacy lease is detected' do
      before do
        allow(Gitlab::ExclusiveLease).to receive(:get_uuid).with(lease_key).and_return('lease_uuid')
      end

      it 'skips scheduling' do
        expect(described_class).not_to receive(:perform_async)

        worker.perform
      end

      it 'skips shard execution' do
        expect(described_class).not_to receive(:perform_async)

        worker.perform(shard_number)
      end
    end

    it 'executes the service under an exclusive lease' do
      expect_to_obtain_exclusive_lease("#{lease_key}/shard/#{shard_number}")

      expect_next_instance_of(::Elastic::ProcessBookkeepingService) do |service|
        expect(service).to receive(:execute).with(shards: [shard_number])
      end

      worker.perform(shard_number)
    end

    it 'only processes items at or below the max score it was queued with' do
      expect_next_instance_of(::Elastic::ProcessBookkeepingService) do |service|
        expect(service).to receive(:execute).with(shards: [shard_number], max_scores: { shard_number => 7 })
      end

      worker.perform(shard_number, 7)
    end

    it 'reads a job from a replica only when it has a max score, even with WAL locations',
      :database_replica, :clean_gitlab_redis_shared_state do
      Sidekiq::Testing.fake! do
        # Requeued while the flag is off for the requeuing job, then pushed again by Sidekiq's scheduler with it on
        stub_feature_flags(search_elastic_bulk_index_replica_reads: false)
        described_class.perform_in(1, shard_number)
        job = described_class.jobs.last
        expect(job).not_to have_key('wal_locations')

        stub_feature_flags(search_elastic_bulk_index_replica_reads: true)
        described_class.jobs.clear
        Sidekiq::Client.new.push(job.except('at'))
        job = described_class.jobs.last
        expect(job['args']).to eq([shard_number])
        expect(job['wal_locations']).to be_present

        used_primary = []
        allow_next_instances_of(::Elastic::ProcessBookkeepingService, 2) do |service|
          allow(service).to receive(:execute) do
            used_primary << Gitlab::Database::LoadBalancing::SessionMap.current(ApplicationRecord.load_balancer)
              .use_primary?
            [0, 0]
          end
        end

        [[shard_number], [shard_number, 7]].each do |args|
          Gitlab::Database::LoadBalancing::SidekiqServerMiddleware.new.call(worker, job.merge('args' => args),
            'default') do
            worker.perform(*args)
          end
        end

        expect(used_primary).to eq([true, false])
      end
    end

    context 'when search cluster is unhealthy' do
      before do
        allow(Search::ClusterHealthCheck::Elastic).to receive(:healthy?).and_return(false)
      end

      it 'does nothing if cluster is not healthy' do
        expect(::Elastic::ProcessBookkeepingService).not_to receive(:new)
        expect(worker).to receive(:log).with(/advanced search cluster is unhealthy/)

        expect(worker.perform).to be(false)
      end
    end

    context 'when indexing is disabled' do
      before do
        stub_ee_application_setting(elasticsearch_indexing: false)
      end

      it 'does nothing if indexing is disabled' do
        expect(::Elastic::ProcessBookkeepingService).not_to receive(:new)

        expect(worker.perform).to be(false)
        expect(described_class).not_to receive(:perform_async)
      end
    end

    context 'when service returns non-zero counter' do
      before do
        allow_next_instance_of(::Elastic::ProcessBookkeepingService) do |service|
          allow(service).to receive(:execute).and_return([15, 0])
        end
      end

      it 'adds logging_extras to the done log' do
        worker.perform(shard_number)

        expect(worker.logging_extras).to eq(
          "#{ApplicationWorker::LOGGING_EXTRA_KEY}.search_elastic_index_bulk_cron_worker.records_count" => 15,
          "#{ApplicationWorker::LOGGING_EXTRA_KEY}.search_elastic_index_bulk_cron_worker.shard_number" => shard_number
        )
      end

      it 'requeues the worker with the current max score' do
        expect(described_class).to receive(:perform_in)
          .with(described_class::RESCHEDULE_INTERVAL, shard_number, max_score)

        worker.perform(shard_number, 7)
      end

      it 'requeues on the primary, so the job records the primary WAL location',
        :database_replica, :clean_gitlab_redis_shared_state do
        allow(::Elastic::ProcessBookkeepingService).to receive(:max_score).and_call_original

        Sidekiq::Testing.fake! do
          expect { worker.perform(shard_number, 7) }.to change { described_class.jobs.size }.by(1)
        end

        job = described_class.jobs.last
        expect(job['args']).to eq([shard_number, 0])
        expect(job['wal_location_sources']).to be_present
        expect(job['wal_location_sources'].values).to all(eq(Gitlab::Database::LoadBalancing::ROLE_PRIMARY.to_s))
      end

      context 'when search_elastic_bulk_index_replica_reads is disabled' do
        before do
          stub_feature_flags(search_elastic_bulk_index_replica_reads: false)
        end

        it 'requeues the worker without a max score' do
          expect(described_class).to receive(:perform_in).with(described_class::RESCHEDULE_INTERVAL, shard_number)

          worker.perform(shard_number)
        end
      end

      context 'when requeue is disabled' do
        before do
          stub_ee_application_setting(elasticsearch_requeue_workers: false)
        end

        it 'does not requeues the worker' do
          expect(described_class).not_to receive(:perform_in).with(described_class::RESCHEDULE_INTERVAL, shard_number)

          worker.perform(shard_number)
        end
      end
    end

    context 'when there are no records in the queue' do
      it 'does not requeue the worker' do
        expect(described_class).not_to receive(:perform_in)

        worker.perform(shard_number)
      end
    end

    context 'when indexing failures occur in the queue' do
      before do
        allow_next_instance_of(::Elastic::ProcessBookkeepingService) do |service|
          allow(service).to receive(:execute).and_return([15, 5])
        end
      end

      it 'does not requeue the worker' do
        expect(described_class).not_to receive(:perform_in)

        worker.perform(shard_number)
      end
    end
  end

  it_behaves_like 'worker with data consistency', described_class,
    data_consistency: :sticky, feature_flag: :search_elastic_bulk_index_replica_reads
end
