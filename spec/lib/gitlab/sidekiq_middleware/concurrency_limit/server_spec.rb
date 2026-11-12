# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Gitlab::SidekiqMiddleware::ConcurrencyLimit::Server, feature_category: :global_search do
  let(:worker_class) do
    Class.new do
      def self.name
        'TestConcurrencyLimitWorker'
      end

      include ApplicationWorker

      concurrency_limit -> { 5 }

      def perform(*)
        self.class.work
      end

      def self.work; end
    end
  end

  let(:worker_class_without_concurrency_limit) do
    Class.new do
      def self.name
        'TestWithoutConcurrencyLimitWorker'
      end

      include ApplicationWorker

      def perform(*)
        self.class.work
      end

      def self.work; end
    end
  end

  let(:worker_klass) { TestConcurrencyLimitWorker }

  before do
    Thread.current[:sidekiq_capsule] = Sidekiq::Capsule.new('test', Sidekiq.default_configuration)
    stub_const('TestConcurrencyLimitWorker', worker_class)
    stub_const('TestWithoutConcurrencyLimitWorker', worker_class_without_concurrency_limit)
    stub_feature_flags(disable_sidekiq_concurrency_limit_middleware_TestConcurrencyLimitWorker: false,
      sidekiq_concurrency_limit_use_free_slots_TestConcurrencyLimitWorker: false)
    stub_feature_flags(disable_sidekiq_concurrency_limit_middleware_TestWithoutConcurrencyLimitWorker: false,
      sidekiq_concurrency_limit_use_free_slots_TestWithoutConcurrencyLimitWorker: false)
  end

  after do
    Thread.current[:sidekiq_capsule] = nil
  end

  around do |example|
    with_sidekiq_server_middleware do |chain|
      chain.add described_class
      Sidekiq::Testing.inline! { example.run }
    end
  end

  shared_examples 'track execution' do
    it 'tracks the execution start and end, and cleans up stale trackers' do
      expect(Gitlab::SidekiqMiddleware::ConcurrencyLimit::ConcurrencyLimitService)
        .to receive(:track_execution_start)
      expect(Gitlab::SidekiqMiddleware::ConcurrencyLimit::ConcurrencyLimitService)
        .to receive(:track_execution_end)
      expect(Gitlab::SidekiqMiddleware::ConcurrencyLimit::ConcurrencyLimitService)
        .to receive(:cleanup_stale_trackers)
      expect(Gitlab::SidekiqMiddleware::ConcurrencyLimit::ConcurrencyLimitService)
        .not_to receive(:untrack_pending_resumed_job)

      worker_klass.perform_async('foo')
    end
  end

  shared_examples 'skip execution tracking' do
    it 'does not track the execution or clean up stale trackers' do
      expect(Gitlab::SidekiqMiddleware::ConcurrencyLimit::ConcurrencyLimitService)
        .not_to receive(:track_execution_start)
      expect(Gitlab::SidekiqMiddleware::ConcurrencyLimit::ConcurrencyLimitService)
        .not_to receive(:track_execution_end)
      expect(Gitlab::SidekiqMiddleware::ConcurrencyLimit::ConcurrencyLimitService)
        .not_to receive(:cleanup_stale_trackers)

      worker_klass.perform_async('foo')
    end
  end

  describe '#call' do
    context 'with a concurrency override', :clean_gitlab_redis_queues_metadata do
      let(:manager) do
        Gitlab::SidekiqMiddleware::ConcurrencyLimit::LimitManager.new(
          worker_name: worker_class.name,
          prefix: Gitlab::SidekiqMiddleware::ConcurrencyLimit::ConcurrencyLimitService::REDIS_KEY_PREFIX
        )
      end

      before do
        allow(Gitlab::SidekiqMiddleware::ConcurrencyLimit::ConcurrencyLimitService)
          .to receive(:has_jobs_in_queue?).and_return(false)
        Gitlab::Redis::QueuesMetadata.with do |redis|
          key = "sidekiq:concurrency_limit:{#{worker_class.name.underscore}}:executing"
          6.times { |index| redis.hset(key, "process:#{index}", Time.now.to_i) }
        end
      end

      it 'allows execution above the class limit' do
        manager.set_override_limit!(10)
        expect(worker_class).to receive(:work)

        worker_class.perform_async('foo')
      end

      it 'defers execution above a lowered override' do
        manager.set_override_limit!(2)
        expect(worker_class).not_to receive(:work)
        expect(Gitlab::SidekiqMiddleware::ConcurrencyLimit::ConcurrencyLimitService).to receive(:add_to_queue!)

        worker_class.perform_async('foo')
      end

      it 'defers execution of an otherwise unlimited worker above its override' do
        allow(worker_class).to receive(:get_concurrency_limit).and_return(0)
        manager.set_override_limit!(2)
        expect(worker_class).not_to receive(:work)
        expect(Gitlab::SidekiqMiddleware::ConcurrencyLimit::ConcurrencyLimitService).to receive(:add_to_queue!)

        worker_class.perform_async('foo')
      end
    end

    context 'when sidekiq_concurrency_limit_middleware feature flag is disabled' do
      before do
        stub_feature_flags(sidekiq_concurrency_limit_middleware: false)
      end

      it 'executes the job' do
        expect(TestConcurrencyLimitWorker).to receive(:work)
        expect(Gitlab::SidekiqLogging::ConcurrencyLimitLogger.instance).not_to receive(:deferred_log)
        expect(Gitlab::SidekiqMiddleware::ConcurrencyLimit::ConcurrencyLimitService).not_to receive(:add_to_queue!)

        TestConcurrencyLimitWorker.perform_async('foo')
      end

      it_behaves_like 'skip execution tracking'

      it 'still releases the pending resumed slot for a resumed job' do
        expect(Gitlab::SidekiqMiddleware::ConcurrencyLimit::ConcurrencyLimitService)
          .not_to receive(:track_execution_start)
        expect(Gitlab::SidekiqMiddleware::ConcurrencyLimit::ConcurrencyLimitService)
          .to receive(:untrack_pending_resumed_job).with(worker_klass.name)

        Gitlab::ApplicationContext.with_raw_context do
          TestConcurrencyLimitWorker.concurrency_limit_resume(Time.now.utc.tv_sec).perform_async('foo')
        end
      end
    end

    context 'when per worker feature flag is enabled' do
      before do
        stub_feature_flags(disable_sidekiq_concurrency_limit_middleware_TestConcurrencyLimitWorker: true)
      end

      it 'executes the job' do
        expect(TestConcurrencyLimitWorker).to receive(:work)
        expect(Gitlab::SidekiqLogging::ConcurrencyLimitLogger.instance).not_to receive(:deferred_log)
        expect(Gitlab::SidekiqMiddleware::ConcurrencyLimit::ConcurrencyLimitService).not_to receive(:add_to_queue!)

        TestConcurrencyLimitWorker.perform_async('foo')
      end

      it_behaves_like 'track execution'
    end

    context 'when there are jobs in the queue' do
      before do
        allow(::Gitlab::SidekiqMiddleware::ConcurrencyLimit::ConcurrencyLimitService).to receive(:has_jobs_in_queue?)
                                                                                           .and_return(true)
      end

      it 'defers the job' do
        expect(TestConcurrencyLimitWorker).not_to receive(:work)
        expect(Gitlab::SidekiqLogging::ConcurrencyLimitLogger.instance).to receive(:deferred_log).and_call_original
        expect(Gitlab::SidekiqMiddleware::ConcurrencyLimit::ConcurrencyLimitService)
          .to receive(:add_to_queue!)
          .with(hash_including('deferred' => true, 'deferred_by' => :concurrency_limit), anything)

        TestConcurrencyLimitWorker.perform_async('foo')
      end

      it 'calls the deferred hook of the worker' do
        allow(Gitlab::SidekiqMiddleware::ConcurrencyLimit::ConcurrencyLimitService).to receive(:add_to_queue!)

        expect(Gitlab::SidekiqMiddleware::ConcurrencyLimit::WorkerHooks)
          .to receive(:deferred).with(TestConcurrencyLimitWorker, hash_including('args' => ['foo']))

        TestConcurrencyLimitWorker.perform_async('foo')
      end

      context 'when only the related_class is set in the context' do
        it 'defers the job' do
          expect(TestConcurrencyLimitWorker).not_to receive(:work)
          expect(Gitlab::SidekiqLogging::ConcurrencyLimitLogger.instance).to receive(:deferred_log).and_call_original
          expect(Gitlab::SidekiqMiddleware::ConcurrencyLimit::ConcurrencyLimitService).to receive(:add_to_queue!)

          related_class = 'Gitlab::SidekiqMiddleware::ConcurrencyLimit::ConcurrencyLimitService'
          Gitlab::ApplicationContext.with_raw_context(related_class: related_class) do
            TestConcurrencyLimitWorker.perform_async('foo')
          end
        end
      end

      context 'when concurrency_limit_resume setter is used' do
        it 'executes the job if resumed' do
          expect(TestConcurrencyLimitWorker).to receive(:work)
          expect(Gitlab::SidekiqLogging::ConcurrencyLimitLogger.instance).not_to receive(:deferred_log)
          expect(Gitlab::SidekiqMiddleware::ConcurrencyLimit::ConcurrencyLimitService).not_to receive(:add_to_queue!)

          Gitlab::ApplicationContext.with_raw_context do
            TestConcurrencyLimitWorker.concurrency_limit_resume(Time.now.utc.tv_sec).perform_async('foo')
          end
        end

        it 'releases the pending resumed slot when the job starts executing' do
          expect(Gitlab::SidekiqMiddleware::ConcurrencyLimit::ConcurrencyLimitService)
            .to receive(:untrack_pending_resumed_job).with(worker_klass.name)

          Gitlab::ApplicationContext.with_raw_context do
            TestConcurrencyLimitWorker.concurrency_limit_resume(Time.now.utc.tv_sec).perform_async('foo')
          end
        end
      end

      context 'when both related class and concurrency_limit_resume setter is used' do
        it 'executes the job if resumed' do
          expect(TestConcurrencyLimitWorker).to receive(:work)
          expect(Gitlab::SidekiqLogging::ConcurrencyLimitLogger.instance).not_to receive(:deferred_log)
          expect(Gitlab::SidekiqMiddleware::ConcurrencyLimit::ConcurrencyLimitService).not_to receive(:add_to_queue!)

          related_class = 'Gitlab::SidekiqMiddleware::ConcurrencyLimit::ConcurrencyLimitService'
          Gitlab::ApplicationContext.with_raw_context(related_class: related_class) do
            TestConcurrencyLimitWorker.concurrency_limit_resume(Time.now.utc.tv_sec).perform_async('foo')
          end
        end
      end
    end

    context 'with a concurrency limit scope', :clean_gitlab_redis_queues_metadata,
      :clean_gitlab_redis_concurrency_limit do
      let_it_be(:group_a) { create(:group) }
      let_it_be(:group_b) { create(:group) }
      let_it_be(:project_a) { create(:project, group: create(:group, parent: group_a)) }
      let_it_be(:project_b) { create(:project, group: group_b) }

      let(:scope_a) { "root_namespace:#{group_a.path}" }
      let(:scope_b) { "root_namespace:#{group_b.path}" }
      let(:service) { Gitlab::SidekiqMiddleware::ConcurrencyLimit::ConcurrencyLimitService }
      let(:executing_key) { "#{service::REDIS_KEY_PREFIX}:{test_scoped_concurrency_limit_worker}:executing" }
      let(:scope_metric) { instance_double(Prometheus::Client::Counter, increment: nil) }

      let(:worker_class_with_scope) do
        Class.new do
          def self.name
            'TestScopedConcurrencyLimitWorker'
          end

          include ApplicationWorker

          concurrency_limit -> { 5 }
          concurrency_limit_scope(:root_namespace, enabled: -> { true }, max_percentage: 0.4)

          def perform(*)
            self.class.work
          end

          def self.work; end
        end
      end

      let(:worker_klass) { TestScopedConcurrencyLimitWorker }

      before do
        stub_const('TestScopedConcurrencyLimitWorker', worker_class_with_scope)
        stub_feature_flags(disable_sidekiq_concurrency_limit_middleware_TestScopedConcurrencyLimitWorker: false,
          disable_sidekiq_concurrency_limit_scope_TestScopedConcurrencyLimitWorker: false,
          sidekiq_concurrency_limit_use_free_slots_TestScopedConcurrencyLimitWorker: false)
        allow(Gitlab::Metrics).to receive(:counter).and_call_original
        allow(Gitlab::Metrics).to receive(:counter)
          .with(:sidekiq_concurrency_limit_scope_deferred_jobs_total, anything).and_return(scope_metric)
      end

      def executing(*scope_keys)
        Gitlab::Redis::QueuesMetadata.with do |r|
          scope_keys.each_with_index do |key, i|
            r.hset(executing_key, "p:tid:#{i}", [Time.now.utc.tv_sec, key].compact.join('|'))
          end
        end
      end

      def perform_async_for(project)
        Gitlab::ApplicationContext.with_context(project: project) { worker_klass.perform_async(project.id) }
      end

      def queue_other_job
        service.add_to_queue!({ 'class' => worker_klass.name, 'args' => [project_a.id], 'jid' => 'queued' }, {})
      end

      it 'runs the job and tracks it under its scope' do
        expect(worker_klass).to receive(:work)
        expect(service).to receive(:track_execution_start).with(worker_klass.name, scope_a, reserved_jid: nil)

        perform_async_for(project_a)
      end

      context 'when the job scope is at its share of the limit' do
        before do
          executing(scope_a, scope_a)
        end

        it 'defers the job with its scope key and counts the deferral', :aggregate_failures do
          expect(worker_klass).not_to receive(:work)
          expect(Gitlab::SidekiqLogging::ConcurrencyLimitLogger.instance).to receive(:deferred_log)
            .with(hash_including('concurrency_limit_scope' => scope_a)).and_call_original
          expect(scope_metric).to receive(:increment)
            .with({ worker: worker_klass.name, scope: 'root_namespace' })

          perform_async_for(project_a)

          queue_key = Gitlab::SidekiqMiddleware::ConcurrencyLimit::QueueManager
            .new(worker_name: worker_klass.name, prefix: service::REDIS_KEY_PREFIX).redis_key
          Gitlab::Redis::ConcurrencyLimit.with do |c|
            deferred = Gitlab::Json::SafeParser.parse(c.lpop("#{queue_key}:scope:#{scope_a}"))
            expect(deferred).to include('args' => [project_a.id], 'concurrency_limit_scope' => scope_a)
          end
        end

        it 'queues the scope so its next jobs wait on enqueue' do
          perform_async_for(project_a)

          expect(service.scope_queued?(worker_klass.name, scope_a)).to be(true)
          expect(service.scope_queued?(worker_klass.name, scope_b)).to be(false)
        end

        it 'still runs jobs of other scopes, even with jobs in the queue' do
          queue_other_job

          expect(worker_klass).to receive(:work)
          expect(service).not_to receive(:add_to_queue!)

          perform_async_for(project_b)
        end
      end

      context 'when resumed jobs of the scope have not started yet' do
        before do
          executing(scope_a)
          service.reserve_resumed_jobs(worker_klass.name, %w[resumed-jid],
            Gitlab::SidekiqMiddleware::ConcurrencyLimit::Scope.for(worker_klass), scope_a)
        end

        it 'defers the job' do
          expect(worker_klass).not_to receive(:work)

          perform_async_for(project_a)
        end
      end

      context 'when the worker is at its limit' do
        before do
          executing(scope_b, nil, nil, nil, nil)
        end

        it 'defers the job without counting a scope deferral' do
          expect(worker_klass).not_to receive(:work)
          expect(service).to receive(:add_to_queue!).with(hash_including('concurrency_limit_scope' => scope_a),
            anything)
          expect(scope_metric).not_to receive(:increment)

          perform_async_for(project_a)
        end
      end

      context 'when the job context has no root namespace' do
        before do
          executing(nil, nil, nil)
        end

        it 'runs the job under the worker limit only, and counts it as unattributed', :aggregate_failures do
          unattributed_metric = instance_double(Prometheus::Client::Counter)
          allow(Gitlab::Metrics).to receive(:counter)
            .with(:sidekiq_concurrency_limit_scope_unattributed_jobs_total, anything).and_return(unattributed_metric)

          expect(unattributed_metric).to receive(:increment)
            .with({ worker: worker_klass.name, scope: 'root_namespace' }).once
          expect(worker_klass).to receive(:work)
          expect(service).to receive(:track_execution_start).with(worker_klass.name, nil, reserved_jid: nil)

          worker_klass.perform_async(non_existing_record_id)
        end
      end

      context 'when the job is resumed with a reserved slot' do
        let(:scope) { Gitlab::SidekiqMiddleware::ConcurrencyLimit::Scope.for(worker_klass) }

        def push_resumed_job
          Sidekiq::Client.push('class' => worker_klass, 'args' => [project_a.id], 'jid' => 'resumed-jid',
            'concurrency_limit_resume' => true, 'concurrency_limit_scope' => scope_a,
            'concurrency_limit_reserved' => true)
        end

        before do
          executing(scope_b)
          service.reserve_resumed_jobs(worker_klass.name, %w[resumed-jid], scope, scope_a)
        end

        it 'runs under its stored scope key, taking over its reservation', :aggregate_failures do
          expect(worker_klass).to receive(:work)
          expect(service).not_to receive(:untrack_pending_resumed_job)
          expect(service).to receive(:track_execution_start)
            .with(worker_klass.name, scope_a, reserved_jid: 'resumed-jid').and_call_original

          # Outside a Sidekiq thread there is no executing entry to replace the reservation with.
          expect { push_resumed_job }.to change { service.concurrent_worker_count(worker_klass.name) }.from(2).to(1)
        end

        context 'when the reservation was cleaned up while the job waited in Sidekiq' do
          before do
            service.release_reserved_jobs(worker_klass.name, %w[resumed-jid])
            executing(scope_b, scope_a, scope_a)
          end

          it 'checks the job against the limits again and defers it' do
            expect(worker_klass).not_to receive(:work)
            expect(service).to receive(:add_to_queue!).with(hash_including('concurrency_limit_scope' => scope_a),
              anything)

            push_resumed_job
          end
        end

        context 'when sidekiq_concurrency_limit_middleware is disabled' do
          before do
            stub_feature_flags(sidekiq_concurrency_limit_middleware: false)
          end

          it 'releases the reservation' do
            expect { push_resumed_job }.to change { service.concurrent_worker_count(worker_klass.name) }.from(2).to(1)
          end
        end
      end

      context 'when the job was deferred and resumed while the scope was off' do
        let(:scope) { Gitlab::SidekiqMiddleware::ConcurrencyLimit::Scope.for(worker_klass) }

        before do
          executing(scope_a, scope_a)
          service.reserve_resumed_jobs(worker_klass.name, %w[resumed-jid], scope, nil)
        end

        it 'releases its unscoped reservation and defers it behind its scope', :aggregate_failures do
          expect(worker_klass).not_to receive(:work)
          expect(service).to receive(:add_to_queue!).with(hash_including('concurrency_limit_scope' => scope_a),
            anything)

          expect do
            Gitlab::ApplicationContext.with_context(project: project_a) do
              Sidekiq::Client.push('class' => worker_klass, 'args' => [project_a.id], 'jid' => 'resumed-jid',
                'concurrency_limit_resume' => true, 'concurrency_limit_reserved' => true)
            end
          end.to change { service.concurrent_worker_count(worker_klass.name) }.from(3).to(2)
        end
      end

      context 'when sidekiq_concurrency_limit_middleware is disabled' do
        before do
          stub_feature_flags(sidekiq_concurrency_limit_middleware: false)
        end

        it 'does not track the job' do
          expect(service).not_to receive(:track_scoped_execution_start)

          perform_async_for(project_a)
        end
      end

      context 'when a job resumed through the pending counter finds its scope at its share' do
        before do
          executing(scope_a, scope_a)
          service.track_pending_resumed_jobs(worker_klass.name, 1)
        end

        it 'defers it again and releases its pending slot' do
          expect(worker_klass).not_to receive(:work)

          expect do
            Sidekiq::Client.push('class' => worker_klass, 'args' => [project_a.id], 'jid' => 'resumed-jid',
              'concurrency_limit_resume' => true, 'concurrency_limit_scope' => scope_a)
          end.to change { service.pending_resumed_jobs_count(worker_klass.name) }.from(1).to(0)
        end
      end

      context 'when the scope is not enabled' do
        before do
          allow(worker_klass.get_concurrency_limit_scope[:enabled]).to receive(:call).and_return(false)
        end

        it 'defers behind queued jobs' do
          queue_other_job

          expect(worker_klass).not_to receive(:work)

          perform_async_for(project_b)
        end
      end

      context 'when the worker also uses free slots' do
        before do
          stub_feature_flags(sidekiq_concurrency_limit_use_free_slots_TestScopedConcurrencyLimitWorker: true)
          executing(scope_a, scope_a)
        end

        it 'still defers the job at its scope share while the worker is below its limit', :aggregate_failures do
          expect(worker_klass).not_to receive(:work)
          expect(service).not_to receive(:track_free_slot_execution_start)
          expect(service).to receive(:add_to_queue!).with(hash_including('concurrency_limit_scope' => scope_a),
            anything)
          expect(scope_metric).to receive(:increment).with({ worker: worker_klass.name, scope: 'root_namespace' })

          perform_async_for(project_a)
        end
      end
    end

    context 'when the worker uses free slots', :clean_gitlab_redis_queues_metadata,
      :clean_gitlab_redis_concurrency_limit do
      include ConcurrencyLimitHelpers

      let(:service) { Gitlab::SidekiqMiddleware::ConcurrencyLimit::ConcurrencyLimitService }

      before do
        stub_feature_flags(sidekiq_concurrency_limit_use_free_slots_TestConcurrencyLimitWorker: true)
      end

      def reserve_resumed_job
        service.reserve_resumed_jobs(worker_klass.name, %w[resumed-jid], nil, nil)
      end

      def push_resumed_job(reserved:)
        Sidekiq::Client.push('class' => worker_klass, 'args' => ['foo'], 'jid' => 'resumed-jid',
          'concurrency_limit_resume' => true, 'concurrency_limit_reserved' => reserved)
      end

      it 'runs the job below the limit despite queued jobs, and tracks it', :aggregate_failures do
        defer_job(worker_klass.name)
        fill_executing_slots(worker_klass.name, 4)

        expect(worker_klass).to receive(:work)
        expect(service).not_to receive(:add_to_queue!)
        expect(service).to receive(:track_execution_start).with(worker_klass.name, nil, reserved_jid: nil)

        worker_klass.perform_async('foo')
      end

      it 'defers the job at the limit' do
        defer_job(worker_klass.name)
        fill_executing_slots(worker_klass.name, 5)

        expect(worker_klass).not_to receive(:work)
        expect(service).to receive(:add_to_queue!)
          .with(hash_including('deferred' => true, 'deferred_by' => :concurrency_limit), anything)

        worker_klass.perform_async('foo')
      end

      context 'when the job is resumed with a reserved slot' do
        before do
          fill_executing_slots(worker_klass.name, 4)
          reserve_resumed_job
        end

        it 'runs at the limit, taking over its reservation', :aggregate_failures do
          expect(worker_klass).to receive(:work)
          expect(service).not_to receive(:untrack_pending_resumed_job)
          expect(service).to receive(:track_execution_start)
            .with(worker_klass.name, nil, reserved_jid: 'resumed-jid').and_call_original

          # Outside a Sidekiq thread there is no executing entry to replace the reservation with.
          expect { push_resumed_job(reserved: true) }
            .to change { service.concurrent_worker_count(worker_klass.name) }.from(5).to(4)
        end

        context 'when the reservation was cleaned up while the job waited in Sidekiq' do
          before do
            service.release_reserved_jobs(worker_klass.name, %w[resumed-jid])
            fill_executing_slots(worker_klass.name, 5)
          end

          it 'checks the job against the limit again and defers it' do
            expect(worker_klass).not_to receive(:work)
            expect(service).to receive(:add_to_queue!)

            push_resumed_job(reserved: true)
          end
        end
      end

      context 'when a job resumed through the pending counter finds the worker at its limit' do
        before do
          fill_executing_slots(worker_klass.name, 5)
          service.track_pending_resumed_jobs(worker_klass.name, 1)
        end

        it 'defers it again and releases its pending slot' do
          expect(worker_klass).not_to receive(:work)

          expect { push_resumed_job(reserved: false) }
            .to change { service.pending_resumed_jobs_count(worker_klass.name) }.from(1).to(0)
        end
      end
    end

    context 'when sidekiq_workers are stubbed' do
      before do
        allow(::Gitlab::SidekiqMiddleware::ConcurrencyLimit::ConcurrencyLimitService).to receive(:over_the_limit?)
                                                                                           .and_return(over_the_limit)
      end

      context 'when under the limit' do
        let(:over_the_limit) { false }

        it 'executes the job' do
          expect(TestConcurrencyLimitWorker).to receive(:work)
          expect(Gitlab::SidekiqLogging::ConcurrencyLimitLogger.instance).not_to receive(:deferred_log)
          expect(Gitlab::SidekiqMiddleware::ConcurrencyLimit::ConcurrencyLimitService).not_to receive(:add_to_queue!)

          TestConcurrencyLimitWorker.perform_async('foo')
        end

        it_behaves_like 'track execution'

        context 'when limit is set to zero' do
          before do
            allow_next_instance_of(::Gitlab::SidekiqMiddleware::ConcurrencyLimit::Middleware) do |instance|
              allow(instance).to receive(:limit_for).and_return(0)
            end
          end

          it_behaves_like 'track execution'
        end

        context 'when limit is not defined' do
          it_behaves_like 'track execution'
        end
      end

      context 'when over the limit' do
        let(:over_the_limit) { true }

        it 'defers the job' do
          expect(TestConcurrencyLimitWorker).not_to receive(:work)
          expect(Gitlab::SidekiqLogging::ConcurrencyLimitLogger.instance).to receive(:deferred_log).and_call_original
          expect(Gitlab::SidekiqMiddleware::ConcurrencyLimit::ConcurrencyLimitService)
            .to receive(:add_to_queue!)
            .with(hash_including('deferred' => true, 'deferred_by' => :concurrency_limit), anything)

          TestConcurrencyLimitWorker.perform_async('foo')
        end
      end

      context 'with worker class without concurrency limit' do
        let(:worker_klass) { TestWithoutConcurrencyLimitWorker }
        let(:over_the_limit) { false }

        it 'executes the job' do
          expect(worker_klass).to receive(:work)
          expect(Gitlab::SidekiqLogging::ConcurrencyLimitLogger.instance).not_to receive(:deferred_log)
          expect(Gitlab::SidekiqMiddleware::ConcurrencyLimit::ConcurrencyLimitService).not_to receive(:add_to_queue!)

          worker_klass.perform_async('foo')
        end

        it_behaves_like 'track execution'
      end
    end
  end
end
