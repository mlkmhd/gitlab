# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Gitlab::SidekiqMiddleware::ConcurrencyLimit::WorkerExecutionTracker,
  :clean_gitlab_redis_queues_metadata, :clean_gitlab_redis_shared_state, feature_category: :global_search do
  include ExclusiveLeaseHelpers

  let(:worker_class) do
    Class.new do
      def self.name
        'DummyWorker'
      end

      include ApplicationWorker
    end
  end

  let(:worker_class_name) { worker_class.name }

  let(:redis_key_prefix) { 'random_prefix' }

  let(:sidekiq_pid) { 'proc-abc' }
  let(:sidekiq_tid) { 'proc-abc' }

  let(:tracking_hash) { "#{redis_key_prefix}:{#{worker_class_name.underscore}}:executing" }
  let(:tracking_elem) { "#{sidekiq_pid}:tid:#{sidekiq_tid}" }

  subject(:service) { described_class.new(worker_name: worker_class_name, prefix: redis_key_prefix) }

  before do
    stub_const(worker_class_name, worker_class)

    Thread.current[:sidekiq_capsule] = Sidekiq::Capsule.new('test', Sidekiq.default_configuration)
    allow(Thread.current[:sidekiq_capsule]).to receive(:identity).and_return(sidekiq_pid)
    allow(service).to receive(:sidekiq_tid).and_return(sidekiq_tid)
  end

  describe '#track_execution_start' do
    subject(:track_execution_start) { service.track_execution_start }

    it 'writes to Redis hash and string' do
      track_execution_start

      Gitlab::Redis::QueuesMetadata.with do |c|
        expect(c.hexists(tracking_hash, tracking_elem)).to be(true)
      end
    end

    context 'with a scope key' do
      subject(:track_execution_start) { service.track_execution_start('namespace:1') }

      it 'stores the scope key beside the start time' do
        freeze_time do
          track_execution_start

          Gitlab::Redis::QueuesMetadata.with do |c|
            expect(c.hget(tracking_hash, tracking_elem)).to eq("#{Time.now.utc.tv_sec}|namespace:1")
          end
        end
      end
    end

    context 'when Thread.current[:sidekiq_capsule] is missing' do
      before do
        Thread.current[:sidekiq_capsule] = nil
      end

      it 'exits early without writing to redis' do
        track_execution_start

        Gitlab::Redis::QueuesMetadata.with do |c|
          expect(c.hexists(tracking_hash, tracking_elem)).to be(false)
        end
      end
    end
  end

  describe '#track_execution_end' do
    subject(:track_execution_end) { service.track_execution_end }

    before do
      service.track_execution_start
    end

    it 'clears to Redis hash and string' do
      Gitlab::Redis::QueuesMetadata.with do |c|
        expect { track_execution_end }
          .to change { c.hexists(tracking_hash, tracking_elem) }.from(true).to(false)
      end
    end

    context 'when Thread.current[:sidekiq_capsule] is missing' do
      before do
        Thread.current[:sidekiq_capsule] = nil
      end

      it 'exits early without writing to redis' do
        Gitlab::Redis::QueuesMetadata.with do |c|
          expect(c.hexists(tracking_hash, tracking_elem)).to be(true)
          track_execution_end
          expect(c.hexists(tracking_hash, tracking_elem)).to be(true)
        end
      end
    end
  end

  describe '#concurrent_worker_count' do
    let(:size) { 10 }

    subject(:concurrent_worker_count) { service.concurrent_worker_count }

    before do
      Gitlab::Redis::QueuesMetadata.with do |c|
        c.hset(tracking_hash, (1..size).flat_map { |i| [i, i] })
      end
    end

    it 'returns hash size' do
      expect(concurrent_worker_count).to eq(size)
    end

    context 'with empty hash' do
      before do
        Gitlab::Redis::QueuesMetadata.with { |c| c.del(tracking_hash) }
      end

      it 'returns 0' do
        expect(concurrent_worker_count).to eq(0)
      end
    end
  end

  describe 'pending resumed jobs tracking' do
    let(:pending_key) { "#{redis_key_prefix}:{#{worker_class_name.underscore}}:pending_resumed" }

    describe '#track_pending_resumed_jobs' do
      it 'increments the counter and sets a TTL' do
        service.track_pending_resumed_jobs(3)

        Gitlab::Redis::QueuesMetadata.with do |c|
          expect(c.get(pending_key).to_i).to eq(3)
          expect(c.ttl(pending_key)).to be_within(5).of(described_class::TRACKING_KEY_TTL.to_i)
        end

        expect { service.track_pending_resumed_jobs(2) }
          .to change { service.pending_resumed_jobs_count }.from(3).to(5)
      end

      it 'does nothing for a non-positive count' do
        expect { service.track_pending_resumed_jobs(0) }
          .not_to change { service.pending_resumed_jobs_count }
        expect { service.track_pending_resumed_jobs(-1) }
          .not_to change { service.pending_resumed_jobs_count }
      end
    end

    describe '#untrack_pending_resumed_job' do
      it 'decrements the counter' do
        service.track_pending_resumed_jobs(2)

        expect { service.untrack_pending_resumed_job }
          .to change { service.pending_resumed_jobs_count }.from(2).to(1)
      end

      it 'floors the counter at zero to absorb drift' do
        expect { service.untrack_pending_resumed_job }
          .not_to change { service.pending_resumed_jobs_count }.from(0)
      end

      it 'decrements by the given count' do
        service.track_pending_resumed_jobs(5)

        expect { service.untrack_pending_resumed_job(3) }
          .to change { service.pending_resumed_jobs_count }.from(5).to(2)
      end

      it 'floors at zero when the count exceeds the counter' do
        service.track_pending_resumed_jobs(2)

        expect { service.untrack_pending_resumed_job(5) }
          .to change { service.pending_resumed_jobs_count }.from(2).to(0)
      end

      it 'does nothing for a non-positive count' do
        service.track_pending_resumed_jobs(2)

        expect { service.untrack_pending_resumed_job(0) }
          .not_to change { service.pending_resumed_jobs_count }
      end
    end

    describe '#pending_resumed_jobs_count' do
      it 'returns zero when nothing is tracked' do
        expect(service.pending_resumed_jobs_count).to eq(0)
      end
    end
  end

  describe '#concurrent_counts_by_scope' do
    subject(:concurrent_counts_by_scope) { service.concurrent_counts_by_scope }

    it 'returns an empty hash when nothing is executing' do
      expect(concurrent_counts_by_scope).to eq({})
    end

    it 'counts executing jobs per scope key, ignoring unscoped jobs' do
      Gitlab::Redis::QueuesMetadata.with do |c|
        c.hset(tracking_hash, 'p:tid:1', '100|namespace:1', 'p:tid:2', '100|namespace:1',
          'p:tid:3', '100|project:2', 'p:tid:4', '100')
      end

      expect(concurrent_counts_by_scope).to eq('namespace:1' => 2, 'project:2' => 1)
      expect(service.concurrent_worker_count).to eq(4)
    end
  end

  describe 'reservations for resumed jobs' do
    def tracked
      Gitlab::Redis::QueuesMetadata.with { |c| c.hgetall(tracking_hash) }
    end

    def reserve(jids, limit: 4, scope_key: 'namespace:1', scope_limit: 2)
      service.reserve_resumed_jobs(jids, limit: limit, scope_key: scope_key, scope_limit: scope_limit)
    end

    describe '#reserve_resumed_jobs' do
      it 'reserves a slot per job, under the scope' do
        freeze_time do
          expect(reserve(%w[j1])).to eq(1)

          expect(tracked).to eq('resumed:j1' => "#{Time.now.utc.tv_sec}|namespace:1")
        end
      end

      it 'stops at the scope share, counting executing jobs of the scope' do
        Gitlab::Redis::QueuesMetadata.with { |c| c.hset(tracking_hash, 'p:tid:1', '1|namespace:1') }

        expect(reserve(%w[j1 j2 j3])).to eq(1)
        expect(tracked.keys).to contain_exactly('p:tid:1', 'resumed:j1')
      end

      it 'stops at the worker limit, counting every scope' do
        Gitlab::Redis::QueuesMetadata.with { |c| c.hset(tracking_hash, 'p:tid:1', '1|namespace:2', 'p:tid:2', '1') }

        expect(reserve(%w[j1 j2 j3], limit: 3, scope_limit: 5)).to eq(1)
      end

      it 'reserves under the worker limit only without a scope key' do
        expect(reserve(%w[j1 j2 j3], limit: 2, scope_key: nil)).to eq(2)
        expect(tracked).to include('resumed:j1' => anything, 'resumed:j2' => anything)
      end

      it 'counts executing jobs and reservations of every scope without a scope key' do
        reserve(%w[j1])
        Gitlab::Redis::QueuesMetadata.with { |c| c.hset(tracking_hash, 'p:tid:1', '1|namespace:2', 'p:tid:2', '1') }

        expect(reserve(%w[j2 j3], scope_key: nil)).to eq(1)
        expect(tracked.keys).to contain_exactly('resumed:j1', 'resumed:j2', 'p:tid:1', 'p:tid:2')
      end

      it 'lets jobs without a jid through without a slot' do
        expect(reserve(['j1', nil, 'j2', 'j3'])).to eq(3)
        expect(tracked.keys).to contain_exactly('resumed:j1', 'resumed:j2')
      end

      it 'counts reserving the same job twice once' do
        reserve(%w[j1])

        expect(reserve(%w[j1 j2])).to eq(2)
        expect(service.concurrent_worker_count).to eq(2)
      end
    end

    describe '#release_reserved_jobs' do
      it 'removes the reservations' do
        reserve(%w[j1 j2])

        service.release_reserved_jobs(%w[j1])

        expect(tracked.keys).to contain_exactly('resumed:j2')
      end
    end

    describe '#track_execution_start with a reserved job' do
      before do
        reserve(%w[j1])
      end

      it 'replaces the reservation with the executing thread' do
        service.track_execution_start('namespace:1', reserved_jid: 'j1')

        expect(tracked.keys).to contain_exactly(tracking_elem)
        expect(service.concurrent_counts_by_scope).to eq('namespace:1' => 1)
      end

      context 'when Thread.current[:sidekiq_capsule] is missing' do
        before do
          Thread.current[:sidekiq_capsule] = nil
        end

        it 'only releases the reservation' do
          service.track_execution_start('namespace:1', reserved_jid: 'j1')

          expect(tracked).to be_empty
        end
      end
    end
  end

  describe '#track_scoped_execution_start' do
    def admit(scope_key = 'namespace:1')
      service.track_scoped_execution_start(limit: 3, scope_key: scope_key, scope_limit: 2)
    end

    it 'tracks the execution when the worker and the scope have room' do
      expect(admit).to be_nil
      expect(service.concurrent_counts_by_scope).to eq('namespace:1' => 1)
    end

    it 'counts reservations against the scope share' do
      service.reserve_resumed_jobs(%w[j1], limit: 3, scope_key: 'namespace:1', scope_limit: 2)
      admit

      expect(admit).to eq(:scope)
    end

    it 'takes over an unscoped reservation even when the admission limit is zero', :aggregate_failures do
      service.reserve_resumed_jobs(%w[j1], limit: 1, scope_key: nil, scope_limit: 0)

      expect(service.track_scoped_execution_start(limit: 0, scope_key: nil, scope_limit: 0,
        reserved_jid: 'j1')).to be_nil
      expect(Gitlab::Redis::QueuesMetadata.with { |c| c.hkeys(tracking_hash) }).to contain_exactly(tracking_elem)
    end

    context 'with the reservation of a resumed job' do
      def admit_reserved
        service.track_scoped_execution_start(limit: 3, scope_key: 'namespace:1', scope_limit: 2, reserved_jid: 'j1')
      end

      before do
        Gitlab::Redis::QueuesMetadata.with { |c| c.hset(tracking_hash, 'other:tid:1', "#{Time.now.utc.tv_sec}|namespace:1") }
      end

      it 'takes over the reservation even though the scope is at its share' do
        service.reserve_resumed_jobs(%w[j1], limit: 3, scope_key: 'namespace:1', scope_limit: 2)

        expect(admit_reserved).to be_nil
        expect(Gitlab::Redis::QueuesMetadata.with { |c| c.hkeys(tracking_hash) })
          .to contain_exactly('other:tid:1', tracking_elem)
      end

      it 'checks the job like a new one once the reservation was cleaned up' do
        Gitlab::Redis::QueuesMetadata.with { |c| c.hset(tracking_hash, 'other:tid:2', "#{Time.now.utc.tv_sec}|namespace:1") }

        expect(admit_reserved).to eq(:scope)
      end

      context 'when the reservation is of another scope' do
        it 'releases it and checks the job like a new one' do
          Gitlab::Redis::QueuesMetadata.with { |c| c.hset(tracking_hash, 'other:tid:2', "#{Time.now.utc.tv_sec}|namespace:1") }
          service.reserve_resumed_jobs(%w[j1], limit: 3, scope_key: nil, scope_limit: 0)

          expect(admit_reserved).to eq(:scope)
          expect(Gitlab::Redis::QueuesMetadata.with { |c| c.hkeys(tracking_hash) })
            .to contain_exactly('other:tid:1', 'other:tid:2')
        end

        it 'admits the job when its scope has room' do
          service.reserve_resumed_jobs(%w[j1], limit: 3, scope_key: 'namespace:2', scope_limit: 2)

          expect(admit_reserved).to be_nil
          expect(Gitlab::Redis::QueuesMetadata.with { |c| c.hkeys(tracking_hash) })
            .to contain_exactly('other:tid:1', tracking_elem)
        end
      end
    end

    it 'counts every scope against the worker limit' do
      service.reserve_resumed_jobs(%w[j1 j2], limit: 3, scope_key: nil, scope_limit: 0)
      admit('namespace:2')

      expect(admit).to eq(:limit)
      expect(service.concurrent_worker_count).to eq(3)
    end

    context 'without a scope key' do
      before do
        service.reserve_resumed_jobs(%w[j1], limit: 3, scope_key: 'namespace:1', scope_limit: 2)
        Gitlab::Redis::QueuesMetadata.with { |c| c.hset(tracking_hash, 'other:tid:1', '1|namespace:1') }
      end

      it 'tracks the execution while the worker has room, ignoring scope shares' do
        expect(admit(nil)).to be_nil
        expect(service.concurrent_worker_count).to eq(3)
      end

      it 'counts executing jobs and reservations of every scope against the worker limit' do
        admit(nil)

        expect(admit(nil)).to eq(:limit)
      end
    end
  end

  describe '#cleanup_stale_trackers' do
    let(:dangling_tid) { 4567 }
    let(:long_running_tid) { 5678 }
    let(:invalid_process_thread_id) { 'proc-abc::4567' }
    let(:dangling_process_thread_id) { 'proc-abc:tid:4567' }
    let(:long_running_process_thread_id) { 'proc-abc:tid:5678' }

    # Format from https://github.com/sidekiq/sidekiq/blob/v7.3.9/lib/sidekiq/api.rb#L1209
    # The tid field in the `{pid}:work` hash contains a hash of 'payload' -> job hash.
    def generate_sidekiq_hash(worker)
      job_hash = { 'payload' => ::Gitlab::Json.dump({
        'class' => worker,
        'created_at' => Time.now.to_f - described_class::TRACKING_KEY_TTL
      }) }

      Sidekiq.dump_json(job_hash)
    end

    subject(:cleanup_stale_trackers) { service.cleanup_stale_trackers }

    context 'when hash is valid' do
      before do
        Gitlab::Redis::QueuesMetadata.with do |r|
          # element should not be deleted since it is within the ttl
          r.hset(tracking_hash, tracking_elem, Time.now.utc.tv_sec - (0.1 * described_class::TRACKING_KEY_TTL.to_i))

          # element should not be deleted since it is a long running process
          r.hset(tracking_hash, long_running_process_thread_id,
            Time.now.utc.tv_sec - (2 * described_class::TRACKING_KEY_TTL.to_i))

          # element should be deleted since hash value is invalid
          r.hset(tracking_hash, invalid_process_thread_id,
            Time.now.utc.tv_sec - (2 * described_class::TRACKING_KEY_TTL.to_i))

          # element should be deleted since it is a long running process
          # but stale as the thread is executing another worker now
          r.hset(tracking_hash, dangling_process_thread_id,
            Time.now.utc.tv_sec - (2 * described_class::TRACKING_KEY_TTL.to_i))
        end

        Gitlab::SidekiqSharding::Validator.allow_unrouted_sidekiq_calls do
          Sidekiq.redis do |r|
            r.hset("proc-abc:work", long_running_tid, generate_sidekiq_hash(worker_class_name))
            r.hset("proc-abc:work", dangling_process_thread_id, generate_sidekiq_hash('otherworker'))
          end
        end
      end

      it 'only cleans up dangling keys' do
        expect { cleanup_stale_trackers }.to change { service.concurrent_worker_count }.from(4).to(2)
      end
    end

    context 'with a reservation of a resumed job that never started' do
      before do
        Gitlab::Redis::QueuesMetadata.with do |r|
          r.hset(tracking_hash, 'resumed:fresh', "#{Time.now.utc.tv_sec}|namespace:1")
          r.hset(tracking_hash, 'resumed:lost',
            (Time.now.utc.tv_sec - (2 * described_class::TRACKING_KEY_TTL.to_i)).to_s)
        end
      end

      it 'removes it once it is older than TRACKING_KEY_TTL' do
        cleanup_stale_trackers

        Gitlab::Redis::QueuesMetadata.with { |r| expect(r.hkeys(tracking_hash)).to contain_exactly('resumed:fresh') }
      end
    end

    context 'when the trackers carry a scope key' do
      before do
        Gitlab::Redis::QueuesMetadata.with do |r|
          r.hset(tracking_hash, tracking_elem, "#{Time.now.utc.tv_sec}|namespace:1")
          r.hset(tracking_hash, dangling_process_thread_id,
            "#{Time.now.utc.tv_sec - (2 * described_class::TRACKING_KEY_TTL.to_i)}|namespace:1")
        end
      end

      it 'cleans up the stale one from the scope counts too' do
        expect { cleanup_stale_trackers }
          .to change { service.concurrent_counts_by_scope }.from('namespace:1' => 2).to('namespace:1' => 1)
      end
    end

    context 'when hash is invalid' do
      let(:invalid_hash) { 'invalid' }

      before do
        Gitlab::Redis::QueuesMetadata.with do |r|
          r.hset(tracking_hash, long_running_process_thread_id,
            Time.now.utc.tv_sec - (2 * described_class::TRACKING_KEY_TTL.to_i))
        end

        Gitlab::SidekiqSharding::Validator.allow_unrouted_sidekiq_calls do
          Sidekiq.redis do |r|
            r.hset("proc-abc:work", long_running_tid, invalid_hash)
          end
        end
      end

      it 'tracks exception' do
        expect(Gitlab::ErrorTracking).to receive(:track_exception).with(instance_of(JSON::ParserError),
          worker_class: 'DummyWorker')

        expect { cleanup_stale_trackers }.to change { service.concurrent_worker_count }.from(1).to(0)
      end
    end

    context 'when lease cannot be obtained' do
      let(:lease_key) { "#{redis_key_prefix}:{#{worker_class_name.underscore}}" }

      before do
        stub_exclusive_lease_taken(lease_key, timeout: described_class::TRACKING_KEY_TTL)
      end

      it 'does not do anything' do
        expect(Gitlab::Redis::QueuesMetadata).not_to receive(:with)

        cleanup_stale_trackers
      end
    end
  end
end
