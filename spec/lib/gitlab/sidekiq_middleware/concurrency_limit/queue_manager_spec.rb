# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Gitlab::SidekiqMiddleware::ConcurrencyLimit::QueueManager,
  :clean_gitlab_redis_shared_state, :clean_gitlab_redis_concurrency_limit, :request_store,
  feature_category: :global_search do
  let(:worker_class) do
    Class.new do
      def self.name
        'DummyWorker'
      end

      include ApplicationWorker

      concurrency_limit -> { 2 }
    end
  end

  let(:worker_class_name) { worker_class.name }

  let(:worker_context) do
    { 'correlation_id' => 'context_correlation_id',
      'meta.project' => 'gitlab-org/gitlab' }
  end

  let(:stored_context) do
    {
      "#{Gitlab::ApplicationContext::LOG_KEY}.project" => 'gitlab-org/gitlab',
      "correlation_id" => 'context_correlation_id'
    }
  end

  let(:job) { { 'args' => [1, 2], 'jid' => 'abc123' } }
  let(:job_with_wal_locations) do
    { 'args' => [1, 2], 'jid' => 'def456', 'wal_locations' => { 'main' => '0/D525E3A8', 'ci' => '0/D525E3A8' } }
  end

  let(:concurrency_service) { Gitlab::SidekiqMiddleware::ConcurrencyLimit::ConcurrencyLimitService }

  subject(:service) { described_class.new(worker_name: worker_class_name, prefix: 'some_prefix') }

  before do
    stub_const(worker_class_name, worker_class)
    stub_feature_flags(sidekiq_concurrency_limit_use_free_slots_DummyWorker: false)
  end

  describe '#head_job_buffered_at' do
    it 'is nil for an empty queue' do
      expect(service.head_job_buffered_at).to be_nil
    end

    it 'returns when the oldest queued job was deferred' do
      travel_to(10.minutes.ago) { service.add_to_queue!(job, worker_context) }
      service.add_to_queue!(job.merge('jid' => 'newer'), worker_context)

      expect(service.head_job_buffered_at).to be_within(1).of(10.minutes.ago.to_f)
    end

    it 'is nil when the oldest entry is malformed' do
      Gitlab::Redis::ConcurrencyLimit.with { |redis| redis.rpush(service.redis_key, 'not json') }

      expect(service.head_job_buffered_at).to be_nil
    end
  end

  describe '#add_to_queue!' do
    subject(:add_to_queue!) { service.add_to_queue!(job, worker_context) }

    it 'adds a job to the set' do
      expect { add_to_queue! }
        .to change { service.queue_size }
        .from(0).to(1)
    end

    it 'adds only one unique job to the set' do
      expect do
        2.times { add_to_queue! }
      end.to change { service.queue_size }.from(0).to(1)
    end

    it 'stores context information' do
      add_to_queue!

      Gitlab::Redis::ConcurrencyLimit.with do |r|
        set_key = service.redis_key
        stored_job = service.send(:deserialize, r.lrange(set_key, 0, -1).first)

        expect(stored_job['context']).to eq(stored_context)
      end
    end

    it 'stores the jid' do
      add_to_queue!

      Gitlab::Redis::ConcurrencyLimit.with do |r|
        set_key = service.redis_key
        stored_job = service.send(:deserialize, r.lrange(set_key, 0, -1).first)

        expect(stored_job['jid']).to eq(job['jid'])
      end
    end

    it 'stores no size-limiter compression markers for an uncompressed job' do
      add_to_queue!

      Gitlab::Redis::ConcurrencyLimit.with do |r|
        stored_job = service.send(:deserialize, r.lrange(service.redis_key, 0, -1).first)

        # `Compressor.compressed?` keys off `has_key?`, so a nil-valued marker looks compressed.
        expect(Gitlab::SidekiqMiddleware::SizeLimiter::Compressor).not_to be_compressed(stored_job)
      end
    end

    context 'with a concurrency limit scope key' do
      subject(:add_to_queue!) { service.add_to_queue!(job.merge('concurrency_limit_scope' => 'namespace:1'), {}) }

      it 'stores the job with its scope key in the scope queue', :aggregate_failures do
        add_to_queue!

        Gitlab::Redis::ConcurrencyLimit.with do |c|
          expect(c.llen(service.redis_key)).to eq(0)
          expect(Gitlab::Json::SafeParser.parse(c.lpop("#{service.redis_key}:scope:namespace:1")))
            .to include('concurrency_limit_scope' => 'namespace:1')
        end
      end

      it 'counts as jobs in the queue' do
        expect { add_to_queue! }.to change { service.has_jobs_in_queue? }.from(false).to(true)
      end
    end

    context 'with wal locations' do
      subject(:add_to_queue!) { service.add_to_queue!(job_with_wal_locations, worker_context) }

      it 'stores wal locations' do
        add_to_queue!

        Gitlab::Redis::ConcurrencyLimit.with do |r|
          set_key = service.redis_key
          stored_job = service.send(:deserialize, r.lrange(set_key, 0, -1).first)

          expect(stored_job['wal_locations']).to eq(job_with_wal_locations['wal_locations'])
        end
      end
    end
  end

  describe '#drop_jobs!' do
    let(:matching_context) { { 'meta.user' => 'target_user' } }
    let(:other_context) { { 'meta.user' => 'other_user' } }

    before do
      service.add_to_queue!(job, matching_context)
      service.add_to_queue!(job.merge('jid' => 'other_jid'), other_context)
    end

    it 'removes matching jobs and returns completed result' do
      result = service.drop_jobs!(matching_context, timeout: 10)

      expect(result).to eq(completed: true, deleted_jobs: 1)
      expect(service.queue_size).to eq(1)
    end

    it 'leaves non-matching jobs intact' do
      service.drop_jobs!(matching_context, timeout: 10)

      Gitlab::Redis::ConcurrencyLimit.with do |redis|
        remaining = redis.lrange(service.redis_key, 0, -1).map { |j| service.send(:deserialize, j) }
        expect(remaining.map { |j| j['context']['meta.user'] }).to contain_exactly('other_user')
      end
    end

    it 'returns 0 deleted_jobs when nothing matches' do
      result = service.drop_jobs!({ 'meta.user' => 'unknown' }, timeout: 10)

      expect(result).to eq(completed: true, deleted_jobs: 0)
      expect(service.queue_size).to eq(2)
    end

    it 'does not remove any job when metadata is empty' do
      result = service.drop_jobs!({}, timeout: 10)

      expect(result).to eq(completed: true, deleted_jobs: 0)
      expect(service.queue_size).to eq(2)
    end

    it 'removes every job when metadata matches the worker class' do
      result = service.drop_jobs!({ 'class' => worker_class_name }, timeout: 10)

      expect(result).to eq(completed: true, deleted_jobs: 2)
      expect(service.queue_size).to eq(0)
    end

    it 'does not remove any job when metadata targets another worker class' do
      result = service.drop_jobs!({ 'class' => 'OtherWorker' }, timeout: 10)

      expect(result).to eq(completed: true, deleted_jobs: 0)
      expect(service.queue_size).to eq(2)
    end

    context 'when timeout is exceeded' do
      before do
        allow(service).to receive(:monotonic_time).and_return(0, 0, 100)
      end

      it 'stops early and returns completed: false' do
        result = service.drop_jobs!(matching_context, timeout: 10)

        expect(result[:completed]).to be(false)
      end
    end

    it 'clears the drop-requested flag once finished' do
      service.drop_jobs!(matching_context, timeout: 10)

      expect(service.send(:drop_requested?)).to be_falsey
    end

    it 'sets the drop-requested flag with a TTL matching the operation budget', :aggregate_failures do
      service.send(:request_drop!, 15)

      drop_key = service.instance_variable_get(:@drop_request_key)
      ttl = Gitlab::Redis::ConcurrencyLimit.with { |redis| redis.ttl(drop_key) }

      expect(service.send(:drop_requested?)).to be_truthy
      expect(ttl).to be_between(1, 15)
    end

    context 'when the resume lease cannot be obtained' do
      before do
        stub_const("#{described_class}::DROP_LOCK_RETRIES", 1)
        stub_const("#{described_class}::DROP_LOCK_SLEEP", 0)
        # Resume is actively holding the shared lease.
        Gitlab::ExclusiveLease.new(service.send(:lease_key), timeout: 1.minute).try_obtain
      end

      it 'does not process the queue and reports completed: false', :aggregate_failures do
        result = service.drop_jobs!(matching_context, timeout: 10)

        expect(result).to eq(completed: false, deleted_jobs: 0)
        expect(service.queue_size).to eq(2)
      end

      it 'still clears the drop-requested flag' do
        service.drop_jobs!(matching_context, timeout: 10)

        expect(service.send(:drop_requested?)).to be_falsey
      end
    end

    context 'when the queue holds a malformed entry' do
      before do
        Gitlab::Redis::ConcurrencyLimit.with { |redis| redis.lpush(service.redis_key, 'not json') }
      end

      it 'skips it and still removes the matching jobs', :aggregate_failures do
        result = service.drop_jobs!(matching_context, timeout: 10)

        expect(result).to eq(completed: true, deleted_jobs: 1)
        expect(service.queue_size).to eq(2)
      end
    end

    context 'when the queue is empty' do
      before do
        Gitlab::Redis::ConcurrencyLimit.with { |redis| redis.del(service.redis_key) }
      end

      it 'skips the drop-request/lock handshake and reports completed', :aggregate_failures do
        expect(service).not_to receive(:request_drop!)

        expect(service.drop_jobs!(matching_context, timeout: 10)).to eq(completed: true, deleted_jobs: 0)
      end
    end

    context 'when the queue spans multiple read batches' do
      before do
        stub_const("#{described_class}::MAX_BATCH_SIZE", 1)

        service.add_to_queue!(job.merge('jid' => 'match_2'), matching_context)
        service.add_to_queue!(job.merge('jid' => 'noise_2'), other_context)
        service.add_to_queue!(job.merge('jid' => 'match_3'), matching_context)
      end

      it 'removes every matching job across batches', :aggregate_failures do
        result = service.drop_jobs!(matching_context, timeout: 10)

        expect(result).to eq(completed: true, deleted_jobs: 3)
        expect(service.queue_size).to eq(2)
      end
    end
  end

  describe '#estimated_queue_size' do
    it 'counts the main queue of an unscoped worker' do
      2.times { service.add_to_queue!(job, worker_context) }

      expect(service.estimated_queue_size).to eq(2)
    end
  end

  describe '#has_jobs_in_queue?' do
    it 'uses queue_size' do
      expect { service.add_to_queue!(job, worker_context) }
        .to change { service.has_jobs_in_queue? }
        .from(false).to(true)
    end
  end

  describe 'backing Redis store' do
    it 'routes through Gitlab::Redis::ConcurrencyLimit' do
      expect(Gitlab::Redis::ConcurrencyLimit).to receive(:with).and_call_original

      service.add_to_queue!(job, worker_context)
    end

    it 'writes the job to the ConcurrencyLimit store' do
      service.add_to_queue!(job, worker_context)

      stored = Gitlab::Redis::ConcurrencyLimit.with { |r| r.lrange(service.redis_key, 0, -1) }

      expect(stored.size).to eq(1)
    end
  end

  describe '#resume_processing!', :clean_gitlab_redis_queues_metadata do
    let(:wal_locations) { { 'main' => '0/D525E3A8', 'ci' => '0/D525E3A8' } }
    let(:jobs) do
      [
        { 'args' => [1], 'jid' => 'jid1', 'wal_locations' => wal_locations },
        { 'args' => [2], 'jid' => 'jid2', 'wal_locations' => wal_locations },
        { 'args' => [3], 'jid' => 'jid3', 'wal_locations' => wal_locations }
      ]
    end

    let(:buffered_at) { Time.now.utc }
    let(:metadata_key) { service.metadata_key }
    let(:expected_metadata) do
      { 'jid' => anything,
        'concurrency_limit_buffered_at' => be_within(1.second).of(buffered_at.to_f),
        'concurrency_limit_resume' => true,
        'wal_locations' => wal_locations }.merge(stored_context)
    end

    before do
      service.remove_instance_variable(:@lease) if service.instance_variable_defined?(:@lease)
      travel_to(buffered_at) do
        jobs.each_with_index do |j, index|
          service.add_to_queue!(j, worker_context.merge({ "index" => index + 1 }))
        end
      end
    end

    shared_examples 'resumes jobs respecting concurrency limit' do
      it 'resumes jobs up to the available capacity and keeps the rest queued', :aggregate_failures do
        expect_next_instance_of(Gitlab::ExclusiveLease) do |el|
          expect(el).to receive(:try_obtain).and_call_original
        end

        expect(Gitlab::SidekiqLogging::ConcurrencyLimitLogger.instance)
          .to receive(:batch_resumed_log)
                .with(worker_class_name, 2)
        expect(Gitlab::SafeRequestStore).to receive(:write).with(
          metadata_key,
          kind_of(Queue)
        ) do |_key, queue|
          job1 = queue.pop
          expect(job1).to match(expected_metadata.merge({ "index" => 1 }))
          job2 = queue.pop
          expect(job2).to match(expected_metadata.merge({ "index" => 2 }))
        end

        expect(worker_class).to receive(:bulk_perform_async).with([[1], [2]])

        resumed = service.resume_processing!

        # The two resumed jobs have not started executing yet, so they occupy the whole
        # limit as pending. The third job stays queued until one of them begins executing.
        expect(resumed).to eq(2)
        expect(service.queue_size).to eq(1)
      end
    end

    it_behaves_like 'resumes jobs respecting concurrency limit'

    context 'when a drop is requested' do
      before do
        service.send(:request_drop!, 30)
      end

      it 'yields the lease without processing the queue', :aggregate_failures do
        expect(worker_class).not_to receive(:bulk_perform_async)

        expect(service.resume_processing!).to eq(0)
        expect(service.queue_size).to eq(3)
      end
    end

    it 'calls the resumed hook of the worker for each resumed job' do
      allow(worker_class).to receive(:bulk_perform_async)

      expect(Gitlab::SidekiqMiddleware::ConcurrencyLimit::WorkerHooks)
        .to receive(:resumed).with(worker_class, hash_including('args' => [1])).ordered
      expect(Gitlab::SidekiqMiddleware::ConcurrencyLimit::WorkerHooks)
        .to receive(:resumed).with(worker_class, hash_including('args' => [2])).ordered

      service.resume_processing!
    end

    it 'drops resumed jobs from the queue' do
      expect_next_instance_of(Gitlab::ExclusiveLease) do |el|
        expect(el).to receive(:try_obtain).and_call_original
      end

      expect(worker_class).to receive(:bulk_perform_async).with([[1], [2]])

      expect { service.resume_processing! }
        .to change { service.queue_size }.from(3).to(1)
    end

    it 'resumes further jobs once pending resumed jobs start executing, preserving order', :aggregate_failures do
      expect(worker_class).to receive(:bulk_perform_async).with([[1], [2]]).ordered
      expect(worker_class).to receive(:bulk_perform_async).with([[3]]).ordered

      expect(service.resume_processing!).to eq(2)
      expect(service.queue_size).to eq(1)

      # Simulate the two resumed jobs starting execution: they leave the pending counter
      # but now count towards concurrent_worker_count, so still no capacity to resume.
      2.times { concurrency_service.untrack_pending_resumed_job(worker_class_name) }
      allow(concurrency_service).to receive(:concurrent_worker_count).with(worker_class_name).and_return(2)

      expect(service.resume_processing!).to eq(0)
      expect(service.queue_size).to eq(1)

      # Once one of them finishes, a slot frees up and the last job is resumed.
      allow(concurrency_service).to receive(:concurrent_worker_count).with(worker_class_name).and_return(1)

      expect(service.resume_processing!).to eq(1)
      expect(service.queue_size).to eq(0)
    end

    context 'when processing longer than deadline' do
      let(:deadline) { instance_double(ActiveSupport::TimeWithZone) }

      before do
        allow(described_class::MAX_PROCESSING_TIME).to receive(:from_now).and_return(deadline)
        allow(deadline).to receive(:future?).and_return(true, false)
      end

      it 'stops processing after the deadline' do
        expect_next_instance_of(Gitlab::ExclusiveLease) do |el|
          expect(el).to receive(:try_obtain).and_call_original
        end

        resumed = service.resume_processing!

        expect(resumed).to eq(2)
        expect(service.queue_size).to eq(1)
      end
    end

    context 'when exclusive lease is already being held' do
      before do
        service.exclusive_lease.try_obtain
      end

      it 'does not perform enqueue' do
        travel_to(buffered_at) do
          jobs.each do |j|
            service.add_to_queue!(j, worker_context)
          end
        end

        expect(worker_class).not_to receive(:concurrency_limit_resume)

        service.resume_processing!
      end
    end

    context 'when worker limit is 0' do
      before do
        worker_class.concurrency_limit -> { 0 }
        stub_const("#{described_class}::MAX_BATCH_SIZE", 1)
      end

      it 'resumes at MAX_BATCH_SIZE per iteration' do
        expect_next_instance_of(Gitlab::ExclusiveLease) do |el|
          expect(el).to receive(:try_obtain).and_call_original
        end

        expect(worker_class).to receive(:bulk_perform_async) do |args|
          expect(args.size).to eq(1)
        end.exactly(3).times

        service.resume_processing!
      end
    end

    context 'when concurrency_limit_eager_resume_processing FF is disabled' do
      before do
        stub_feature_flags(concurrency_limit_eager_resume_processing: false)
      end

      it 'resumes processing once' do
        expect_next_instance_of(Gitlab::ExclusiveLease) do |el|
          expect(el).to receive(:try_obtain).and_call_original
        end
        expect(worker_class).to receive(:bulk_perform_async).once.and_call_original

        resumed = service.resume_processing!

        expect(resumed).to eq(2)
        expect(service.queue_size).to eq(1)
      end
    end

    context 'when the worker uses free slots' do
      let(:resumed_args) { [] }

      before do
        stub_feature_flags(sidekiq_concurrency_limit_use_free_slots_DummyWorker: true)
        allow(worker_class).to receive(:bulk_perform_async) { |args| resumed_args.concat(args) }
      end

      it 'reserves a slot per resumed job instead of using the pending counter', :aggregate_failures do
        expect(service.resume_processing!).to eq(2)

        expect(resumed_args).to contain_exactly([1], [2])
        expect(concurrency_service.concurrent_worker_count(worker_class_name)).to eq(2)
        expect(concurrency_service.pending_resumed_jobs_count(worker_class_name)).to eq(0)
        expect(service.queue_size).to eq(1)
      end

      it 'marks the resumed jobs as reserved' do
        metadata = []
        allow(Gitlab::SafeRequestStore).to receive(:write).with(metadata_key, kind_of(Queue)) do |_key, queue|
          metadata.concat(Array.new(queue.size) { queue.pop })
        end

        service.resume_processing!

        expect(metadata).to all(include('concurrency_limit_reserved' => true))
      end

      context 'when the oldest queued job is past the age cap' do
        let(:buffered_at) { 10.minutes.ago }

        it 'reserves against the full limit, not the admission limit' do
          expect(service.resume_processing!).to eq(2)
        end
      end

      context 'when the worker limit is 0' do
        before do
          allow(worker_class).to receive(:get_concurrency_limit).and_return(0)
        end

        it 'resumes without reserving', :aggregate_failures do
          expect(service.resume_processing!).to eq(3)
          expect(concurrency_service.concurrent_worker_count(worker_class_name)).to eq(0)
        end
      end
    end

    context 'with a concurrency limit scope' do
      let(:worker_class) do
        Class.new do
          def self.name
            'DummyWorker'
          end

          include ApplicationWorker

          concurrency_limit -> { 4 }
          concurrency_limit_scope(:root_namespace, enabled: -> { true }, max_percentage: 0.5)
        end
      end

      let(:jobs) do
        [
          ['a1', 'namespace:1'], ['a2', 'namespace:1'], ['a3', 'namespace:1'],
          ['b1', 'namespace:2'], ['u1', nil], ['a4', 'namespace:1']
        ].each_with_index.map do |(jid, scope_key), index|
          { 'args' => [index + 1], 'jid' => jid, 'wal_locations' => wal_locations,
            'concurrency_limit_scope' => scope_key }.compact
        end
      end

      let(:resumed_args) { [] }

      def queued_jids(scope_key = nil)
        key = scope_key ? "#{service.redis_key}:scope:#{scope_key}" : service.redis_key
        Gitlab::Redis::ConcurrencyLimit.with do |c|
          c.lrange(key, 0, -1).map { |j| Gitlab::Json::SafeParser.parse(j)['jid'] }
        end
      end

      def queued_scopes
        Gitlab::Redis::ConcurrencyLimit.with { |c| c.smembers("some_prefix:throttled_scopes:{dummy_worker}") }
      end

      # Commands touching the scopes set, as [name, *args]. A pipeline is one entry, named by its first command.
      def scopes_set_commands(&)
        RedisCommands::Recorder.new(pattern: 'throttled_scopes', &).log.map do |name, *args|
          [name.to_s.downcase, *args]
        end
      end

      def command_names(log)
        log.map(&:first)
      end

      before do
        stub_feature_flags(disable_sidekiq_concurrency_limit_scope_DummyWorker: false)
        allow(worker_class).to receive(:bulk_perform_async) { |args| resumed_args.concat(args) }
      end

      it 'queues jobs with a scope key per scope' do
        expect(queued_jids).to eq(%w[u1])
        expect(queued_jids('namespace:1')).to eq(%w[a1 a2 a3 a4])
        expect(queued_jids('namespace:2')).to eq(%w[b1])
        expect(queued_scopes).to contain_exactly('namespace:1', 'namespace:2')
        expect(service.queue_size).to eq(6)
      end

      it 'resumes each scope up to its share, keeping the rest queued', :aggregate_failures do
        expect(service.resume_processing!).to eq(4)

        expect(resumed_args).to contain_exactly([1], [2], [4], [5])
        expect(queued_jids('namespace:1')).to eq(%w[a3 a4])
        expect(queued_scopes).to contain_exactly('namespace:1')
        expect(service.queue_size).to eq(2)
      end

      it 'reserves a slot per resumed job instead of using the pending counter', :aggregate_failures do
        service.resume_processing!

        expect(concurrency_service.concurrent_counts_by_scope(worker_class_name))
          .to eq('namespace:1' => 2, 'namespace:2' => 1)
        expect(concurrency_service.concurrent_worker_count(worker_class_name)).to eq(4)
        expect(concurrency_service.pending_resumed_jobs_count(worker_class_name)).to eq(0)
      end

      context 'when the worker also uses free slots' do
        before do
          stub_feature_flags(sidekiq_concurrency_limit_use_free_slots_DummyWorker: true)
        end

        it 'still resumes each scope up to its share with scoped reservations', :aggregate_failures do
          expect(service.resume_processing!).to eq(4)

          expect(concurrency_service.concurrent_counts_by_scope(worker_class_name))
            .to eq('namespace:1' => 2, 'namespace:2' => 1)
          expect(queued_jids('namespace:1')).to eq(%w[a3 a4])
          expect(service.queue_size).to eq(2)
        end
      end

      context 'when the scope is turned off and the worker uses free slots' do
        before do
          stub_feature_flags(disable_sidekiq_concurrency_limit_scope_DummyWorker: true,
            sidekiq_concurrency_limit_use_free_slots_DummyWorker: true)
        end

        it 'resumes the scope-queued jobs with unscoped reservations', :aggregate_failures do
          expect(service.resume_processing!).to eq(4)

          expect(concurrency_service.concurrent_worker_count(worker_class_name)).to eq(4)
          expect(concurrency_service.concurrent_counts_by_scope(worker_class_name)).to eq({})
          expect(concurrency_service.pending_resumed_jobs_count(worker_class_name)).to eq(0)
          expect(service.queue_size).to eq(2)
        end
      end

      it 'replays the scope key and the reservation onto the resumed jobs' do
        metadata = []
        allow(Gitlab::SafeRequestStore).to receive(:write).with(metadata_key, kind_of(Queue)) do |_key, queue|
          metadata.concat(Array.new(queue.size) { queue.pop })
        end

        service.resume_processing!

        expect(metadata.map { |m| m['concurrency_limit_scope'] })
          .to contain_exactly('namespace:1', 'namespace:1', 'namespace:2', nil)
        expect(metadata).to all(include('concurrency_limit_reserved' => true))
      end

      context 'when other scopes fill the worker limit' do
        before do
          concurrency_service.reserve_resumed_jobs(worker_class_name, %w[x1 x2], scope_for_worker, 'namespace:8')
          concurrency_service.reserve_resumed_jobs(worker_class_name, %w[x3 x4], scope_for_worker, 'namespace:9')
        end

        let(:scope_for_worker) { Gitlab::SidekiqMiddleware::ConcurrencyLimit::Scope.for(worker_class) }

        it 'resumes only up to the worker limit across all scopes' do
          expect(service.resume_processing!).to eq(0)
          expect(service.queue_size).to eq(6)
        end
      end

      context 'when a scope with a long backlog is at its share' do
        before do
          concurrency_service.reserve_resumed_jobs(worker_class_name, %w[x1 x2],
            Gitlab::SidekiqMiddleware::ConcurrencyLimit::Scope.for(worker_class), 'namespace:1')
        end

        it 'still resumes the other scopes' do
          expect(service.resume_processing!).to eq(2)

          expect(resumed_args).to contain_exactly([4], [5])
          expect(queued_jids('namespace:1')).to eq(%w[a1 a2 a3 a4])
        end
      end

      context 'when bulk_perform_async raises a transient error for a scope' do
        before do
          allow(worker_class).to receive(:bulk_perform_async).with([[1], [2]]).and_raise(Redis::ConnectionError)
        end

        it 'releases that scope reservations and keeps its jobs queued', :aggregate_failures do
          expect { service.resume_processing! }.to raise_error(Redis::ConnectionError)

          expect(concurrency_service.concurrent_counts_by_scope(worker_class_name)).not_to have_key('namespace:1')
          expect(queued_jids('namespace:1')).to eq(%w[a1 a2 a3 a4])
        end
      end

      context 'when a resumed job of a scope is a poison job' do
        before do
          stub_feature_flags(concurrency_limit_eager_resume_processing: false)
          poison = Gitlab::SidekiqMiddleware::SizeLimiter::ExceedLimitError.new(worker_class, 1, 0)
          allow(worker_class).to receive(:bulk_perform_async).with([[1], [2]]).and_raise(poison)
          allow(worker_class).to receive(:bulk_perform_async).with([[2]]).and_raise(poison)
        end

        it 'sends the others individually and removes the batch from the scope queue', :aggregate_failures do
          expect(service.resume_processing!).to eq(4)

          expect(resumed_args).to contain_exactly([1], [4], [5])
          expect(queued_jids('namespace:1')).to eq(%w[a3 a4])
        end

        it 'releases the dropped job reservation' do
          service.resume_processing!

          expect(concurrency_service.concurrent_counts_by_scope(worker_class_name)['namespace:1']).to eq(1)
        end
      end

      context 'when a job sent individually raises a transient error' do
        before do
          stub_feature_flags(concurrency_limit_eager_resume_processing: false)
          poison = Gitlab::SidekiqMiddleware::SizeLimiter::ExceedLimitError.new(worker_class, 1, 0)
          allow(worker_class).to receive(:bulk_perform_async).with([[1], [2]]).and_raise(poison)
          allow(worker_class).to receive(:bulk_perform_async).with([[1]]).and_raise(poison)
          allow(worker_class).to receive(:bulk_perform_async).with([[2]]).and_raise(Redis::ConnectionError)
        end

        it 'releases the reservations of the jobs it did not send and trims the dropped one', :aggregate_failures do
          expect { service.resume_processing! }.to raise_error(Redis::ConnectionError)

          expect(concurrency_service.concurrent_counts_by_scope(worker_class_name)).not_to have_key('namespace:1')
          expect(queued_jids('namespace:1')).to eq(%w[a2 a3 a4])
        end
      end

      context 'when a queued job of a scope is malformed' do
        before do
          # Queues are visited in random order: leave room for all of them so the malformed one is always reached.
          worker_class.concurrency_limit -> { 10 }
          Gitlab::Redis::ConcurrencyLimit.with do |c|
            c.lpush("#{service.redis_key}:scope:namespace:3", 'not json')
            c.sadd("some_prefix:throttled_scopes:{dummy_worker}", 'namespace:3')
          end
        end

        it 'drops it without reserving a slot for it', :aggregate_failures do
          service.resume_processing!

          expect(concurrency_service.concurrent_counts_by_scope(worker_class_name)).not_to have_key('namespace:3')
          expect(queued_jids('namespace:3')).to be_empty
        end
      end

      context 'when the scope is not enabled' do
        before do
          allow(worker_class.get_concurrency_limit_scope[:enabled]).to receive(:call).and_return(false)
        end

        it 'still drains the scope queues, under the worker limit only, without reservations' do
          expect(service.resume_processing!).to eq(4)

          expect(service.queue_size).to eq(2)
          expect(concurrency_service.concurrent_worker_count(worker_class_name)).to eq(0)
          expect(concurrency_service.pending_resumed_jobs_count(worker_class_name)).to eq(4)
        end
      end

      describe '#drop_jobs!' do
        it 'drops matching jobs from every queue and forgets emptied scopes' do
          result = service.drop_jobs!({ 'index' => 4 }, timeout: 10)

          expect(result).to eq(completed: true, deleted_jobs: 1)
          expect(queued_scopes).to contain_exactly('namespace:1')
          expect(service.queue_size).to eq(5)
        end

        it 'drops across several queues' do
          result = service.drop_jobs!({ 'correlation_id' => 'context_correlation_id' }, timeout: 10)

          expect(result).to eq(completed: true, deleted_jobs: 6)
          expect(service.queue_size).to eq(0)
          expect(queued_scopes).to be_empty
        end

        it 'stops before the remaining queues once the timeout is exceeded' do
          allow(service).to receive(:monotonic_time).and_return(0, 100)

          result = service.drop_jobs!({ 'correlation_id' => 'context_correlation_id' }, timeout: 10)

          expect(result).to eq(completed: false, deleted_jobs: 0)
          expect(service.queue_size).to eq(6)
          expect(service).to have_received(:monotonic_time).twice
        end

        it 'scans the scopes set in batches instead of reading it whole', :aggregate_failures do
          stub_const("#{described_class}::MAX_SCOPE_SAMPLE", 1)

          log = scopes_set_commands do
            expect(service.drop_jobs!({ 'correlation_id' => 'context_correlation_id' }, timeout: 10))
              .to eq(completed: true, deleted_jobs: 6)
          end

          expect(command_names(log)).to include('sscan')
          expect(command_names(log)).not_to include('smembers')
        end
      end

      describe 'sampling the queued scopes' do
        def resumed_jids
          resumed_args.map { |(index)| "j#{index}" }
        end

        it 'draws once when fewer scopes are queued than requested, so the whole set is served' do
          log = scopes_set_commands { expect(service.resume_processing!).to eq(4) }

          expect(command_names(log).count('srandmember')).to eq(1)
        end

        context 'with more scopes queued than a pass can serve' do
          let(:jobs) do
            Array.new(20) do |index|
              { 'args' => [index], 'jid' => "j#{index}", 'wal_locations' => wal_locations,
                'concurrency_limit_scope' => "namespace:#{index}" }
            end
          end

          it 'draws a bounded sample per pass and serves every scope across passes', :aggregate_failures do
            per_pass = []

            log = scopes_set_commands do
              10.times do
                break unless service.has_jobs_in_queue?

                per_pass << service.resume_processing!
                concurrency_service.release_reserved_jobs(worker_class_name, resumed_jids)
              end
            end

            expect(per_pass).to eq([4] * 5)
            expect(resumed_args.flatten).to match_array(0...20)
            expect(command_names(log)).not_to include('smembers')
            expect(log.select { |name, *| name == 'srandmember' }.map { |*, count| count.to_i }).to all(be <= 8)
          end
        end

        context 'when the drawn scopes are at their share' do
          let(:jobs) do
            %w[a1 a2 a3].map do |jid|
              { 'args' => [1], 'jid' => jid, 'wal_locations' => wal_locations,
                'concurrency_limit_scope' => 'namespace:1' }
            end
          end

          before do
            stub_const("#{described_class}::MAX_SCOPE_SAMPLE", 1)
            concurrency_service.reserve_resumed_jobs(worker_class_name, %w[x1 x2],
              Gitlab::SidekiqMiddleware::ConcurrencyLimit::Scope.for(worker_class), 'namespace:1')
          end

          it 'redraws while slots remain, a bounded number of times', :aggregate_failures do
            log = scopes_set_commands { expect(service.resume_processing!).to eq(0) }

            expect(command_names(log).count('srandmember')).to eq(described_class::MAX_SCOPE_DRAWS)
            expect(queued_jids('namespace:1')).to eq(%w[a1 a2 a3])
          end
        end
      end

      describe 'counting the queued jobs' do
        let(:jobs) do
          [['a1', 'namespace:1'], ['b1', 'namespace:2'], ['b2', 'namespace:2'], ['b3', 'namespace:2']].map do |jid, key|
            { 'args' => [1], 'jid' => jid, 'wal_locations' => wal_locations, 'concurrency_limit_scope' => key }
          end
        end

        describe '#queue_size' do
          it 'counts every scope queue exactly, scanning the scopes set in batches', :aggregate_failures do
            stub_const("#{described_class}::MAX_SCOPE_SAMPLE", 1)

            log = scopes_set_commands { expect(service.queue_size).to eq(4) }

            expect(command_names(log)).to include('sscan')
            expect(command_names(log)).not_to include('smembers', 'srandmember')
          end
        end

        describe '#estimated_queue_size' do
          it 'counts every scope queue while the scopes set fits in one sample' do
            expect(service.estimated_queue_size).to eq(4)
          end

          it 'extrapolates from a sample of the scope queues beyond that' do
            stub_const("#{described_class}::MAX_SCOPE_SAMPLE", 1)

            # One of the two scopes is sampled, holding 1 or 3 jobs.
            expect(service.estimated_queue_size).to be_in([2, 6])
          end
        end
      end
    end

    context 'when bulk_perform_async raises a non-transient error' do
      let(:poison_error) do
        Gitlab::SidekiqMiddleware::SizeLimiter::ExceedLimitError.new('DummyWorker', 2_000_000, 1_000_000)
      end

      context 'with a mixed batch containing one poison job' do
        before do
          allow(worker_class).to receive(:bulk_perform_async).with([[1], [2]]).and_raise(poison_error)
          allow(worker_class).to receive(:bulk_perform_async).with([[1]]).and_return(nil)
          allow(worker_class).to receive(:bulk_perform_async).with([[2]]).and_raise(poison_error)
          allow(worker_class).to receive(:bulk_perform_async).with([[3]]).and_return(nil)
        end

        it 'enqueues good jobs, drops the poison job, and advances the queue', :aggregate_failures do
          expect_next_instance_of(Gitlab::ExclusiveLease) do |el|
            expect(el).to receive(:try_obtain).and_call_original
          end

          expect(Gitlab::SidekiqLogging::ConcurrencyLimitLogger.instance)
            .to receive(:dropped_poison_job_log)
            .with(worker_class_name, kind_of(String), poison_error)
            .at_least(:once)

          service.resume_processing!

          expect(service.queue_size).to eq(0)
        end

        it 'counts only the enqueued jobs as pending, not the dropped or retried ones' do
          expect_next_instance_of(Gitlab::ExclusiveLease) do |el|
            expect(el).to receive(:try_obtain).and_call_original
          end

          service.resume_processing!

          # Jobs [1] and [3] were enqueued (one pending slot each); the poison job [2] was
          # rolled back and dropped. Anything other than 2 means the batch-level rollback and
          # the per-job re-tracking did not net out (double-count or a counted dropped job).
          expect(concurrency_service.pending_resumed_jobs_count(worker_class_name)).to eq(2)
        end

        it 'increments the dropped_jobs metric for poison jobs', :aggregate_failures do
          expect_next_instance_of(Gitlab::ExclusiveLease) do |el|
            expect(el).to receive(:try_obtain).and_call_original
          end

          counter = service.send(:dropped_job_counter)

          expect(counter).to receive(:increment).with({ worker: worker_class_name }).at_least(:once)

          service.resume_processing!
        end
      end

      context 'when all jobs in a batch are poison jobs' do
        let(:jobs) do
          [
            { 'args' => [1], 'jid' => 'jid1', 'wal_locations' => wal_locations },
            { 'args' => [2], 'jid' => 'jid2', 'wal_locations' => wal_locations }
          ]
        end

        it 'drops all jobs and advances the queue' do
          expect_next_instance_of(Gitlab::ExclusiveLease) do |el|
            expect(el).to receive(:try_obtain).and_call_original
          end

          allow(worker_class).to receive(:bulk_perform_async).and_raise(poison_error)

          service.resume_processing!

          expect(service.queue_size).to eq(0)
        end
      end
    end

    context 'when a job sent individually raises a transient error' do
      before do
        poison = Gitlab::SidekiqMiddleware::SizeLimiter::ExceedLimitError.new('DummyWorker', 2_000_000, 1_000_000)
        allow(worker_class).to receive(:bulk_perform_async).with([[1], [2]]).and_raise(poison)
        allow(worker_class).to receive(:bulk_perform_async).with([[1]]).and_return(nil)
        allow(worker_class).to receive(:bulk_perform_async).with([[2]]).and_raise(Redis::ConnectionError)
      end

      it 'trims the jobs already sent and keeps the rest queued' do
        expect { service.resume_processing! }.to raise_error(Redis::ConnectionError)

        expect(service.queue_size).to eq(2)
      end
    end

    context 'when bulk_perform_async raises a transient error' do
      it 're-raises the error without advancing the queue' do
        expect_next_instance_of(Gitlab::ExclusiveLease) do |el|
          expect(el).to receive(:try_obtain).and_call_original
        end

        allow(worker_class).to receive(:bulk_perform_async)
          .and_raise(Redis::ConnectionError, 'Connection refused')

        expect { service.resume_processing! }.to raise_error(Redis::ConnectionError)

        expect(service.queue_size).to eq(3)
        # The batch was never enqueued, so the slots reserved before bulk_perform_async must
        # be rolled back rather than left inflating the counter until the TTL expires.
        expect(concurrency_service.pending_resumed_jobs_count(worker_class_name)).to eq(0)
      end
    end

    context 'when lease needs to be renewed during processing' do
      before do
        stub_feature_flags(concurrency_limit_eager_resume_processing: true)
      end

      it 'renews the lease before each batch to prevent expiration' do
        lease_instance = instance_double(Gitlab::ExclusiveLease)
        allow(lease_instance).to receive_messages(try_obtain: 'lease_uuid', renew: 'lease_uuid')
        allow(Gitlab::ExclusiveLease).to receive(:new).and_return(lease_instance)

        expect(worker_class).to receive(:bulk_perform_async).with([[1], [2]])

        # Verify that renew is called before each iteration of the loop.
        # With 3 jobs and concurrency limit of 2: the first iteration resumes 2 jobs which
        # then occupy the limit as pending, so the second iteration finds no capacity and
        # breaks. So renew is called twice (before each iteration).
        expect(lease_instance).to receive(:renew).twice

        service.resume_processing!
      end
    end

    # Sidekiq's scheduler re-pushes already-compressed scheduled/retried jobs
    # through the client chain, so a buffered job can arrive compressed.
    context 'when a buffered job carries a size-limiter compressed payload' do
      let(:compressor) { Gitlab::SidekiqMiddleware::SizeLimiter::Compressor }
      let(:original_args) { [1, 'a' * 200] }
      let(:compressed_job) do
        { 'args' => original_args, 'jid' => 'jid1', 'wal_locations' => wal_locations }.tap do |job|
          compressor.compress(job, Sidekiq.dump_json(original_args))
        end
      end

      let(:jobs) { [compressed_job] }

      it 'resumes a job that decompresses back to the original arguments', :aggregate_failures do
        expect_next_instance_of(Gitlab::ExclusiveLease) do |el|
          expect(el).to receive(:try_obtain).and_call_original
        end

        captured_metadata = nil
        allow(Gitlab::SafeRequestStore).to receive(:write).and_call_original
        allow(Gitlab::SafeRequestStore).to receive(:write).with(metadata_key, kind_of(Queue)) do |_key, queue|
          captured_metadata = queue.pop
        end

        resumed_args = nil
        expect(worker_class).to receive(:bulk_perform_async) { |args_list| resumed_args = args_list.first }

        service.resume_processing!

        # Rebuild as ConcurrencyLimit::Resume does, then run server-side decompression.
        resumed_job = { 'class' => worker_class_name, 'args' => resumed_args }.merge(captured_metadata)
        expect(compressor).to be_compressed(resumed_job)

        compressor.decompress(resumed_job)
        expect(resumed_job['args']).to eq(original_args)
      end
    end
  end
end
