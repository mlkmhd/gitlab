# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Gitlab::SidekiqMiddleware::ConcurrencyLimit::Client, :clean_gitlab_redis_queues, feature_category: :global_search do
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

  before do
    stub_const('TestConcurrencyLimitWorker', worker_class)
    stub_feature_flags(disable_sidekiq_concurrency_limit_middleware_TestConcurrencyLimitWorker: false,
      sidekiq_concurrency_limit_use_free_slots_TestConcurrencyLimitWorker: false)
  end

  describe '#call' do
    context 'with an override on an otherwise unlimited worker', :clean_gitlab_redis_queues_metadata do
      let(:manager) do
        Gitlab::SidekiqMiddleware::ConcurrencyLimit::LimitManager.new(
          worker_name: worker_class.name,
          prefix: Gitlab::SidekiqMiddleware::ConcurrencyLimit::ConcurrencyLimitService::REDIS_KEY_PREFIX
        )
      end

      before do
        allow(worker_class).to receive(:get_concurrency_limit).and_return(0)
        allow(Gitlab::SidekiqMiddleware::ConcurrencyLimit::ConcurrencyLimitService)
          .to receive(:has_jobs_in_queue?).with(worker_class.name).and_return(true)
        manager.set_override_limit!(2)
      end

      it 'schedules the job without reading the override' do
        expect(Gitlab::SidekiqMiddleware::ConcurrencyLimit::ConcurrencyLimitService).not_to receive(:current_limit)
        expect(Gitlab::SidekiqMiddleware::ConcurrencyLimit::ConcurrencyLimitService).not_to receive(:add_to_queue!)

        worker_class.perform_async('foo')

        expect(worker_class.jobs.size).to eq(1)
      end
    end

    context 'when the worker class cannot be resolved' do
      it 'schedules the job' do
        middleware = Gitlab::SidekiqMiddleware::ConcurrencyLimit::Middleware.new('UnknownWorker', { 'args' => [] })

        expect(Gitlab::SidekiqMiddleware::ConcurrencyLimit::ConcurrencyLimitService).not_to receive(:add_to_queue!)
        expect { |block| middleware.schedule(&block) }.to yield_control
      end
    end

    context 'when feature flag is disabled' do
      before do
        stub_feature_flags(sidekiq_concurrency_limit_middleware: false)
      end

      it 'schedules the job' do
        expect(Gitlab::SidekiqMiddleware::ConcurrencyLimit::ConcurrencyLimitService).not_to receive(:add_to_queue!)

        TestConcurrencyLimitWorker.perform_async('foo')

        expect(TestConcurrencyLimitWorker.jobs.size).to eq(1)
      end
    end

    context 'when per worker feature flag is enabled' do
      before do
        stub_feature_flags(disable_sidekiq_concurrency_limit_middleware_TestConcurrencyLimitWorker: true)
      end

      it 'schedules the job' do
        expect(Gitlab::SidekiqMiddleware::ConcurrencyLimit::ConcurrencyLimitService).not_to receive(:add_to_queue!)

        TestConcurrencyLimitWorker.perform_async('foo')

        expect(TestConcurrencyLimitWorker.jobs.size).to eq(1)
      end
    end

    context 'when the worker has a concurrency limit scope', :clean_gitlab_redis_queues_metadata,
      :clean_gitlab_redis_concurrency_limit do
      let(:service) { Gitlab::SidekiqMiddleware::ConcurrencyLimit::ConcurrencyLimitService }
      let(:executing_key) { "#{service::REDIS_KEY_PREFIX}:{test_concurrency_limit_worker}:executing" }

      def perform_async_for(group)
        Labkit::Context.with_context(root_namespace: group) { TestConcurrencyLimitWorker.perform_async(1) }
      end

      before do
        stub_feature_flags(disable_sidekiq_concurrency_limit_scope_TestConcurrencyLimitWorker: false)
        worker_class.concurrency_limit_scope(:root_namespace, enabled: -> { true }, max_percentage: 0.4)
        service.add_to_queue!({ 'class' => worker_class.name, 'args' => [1], 'jid' => 'queued',
                                'concurrency_limit_scope' => 'root_namespace:group-1' }, {})
      end

      it 'schedules jobs of other scopes despite the queued job, storing their scope key' do
        expect(service).not_to receive(:add_to_queue!)

        perform_async_for('group-2')

        expect(TestConcurrencyLimitWorker.jobs)
          .to contain_exactly(hash_including('concurrency_limit_scope' => 'root_namespace:group-2'))
      end

      it 'defers jobs of a scope with queued jobs behind them' do
        expect(service).to receive(:add_to_queue!)
          .with(hash_including('concurrency_limit_scope' => 'root_namespace:group-1'), anything)

        perform_async_for('group-1')

        expect(TestConcurrencyLimitWorker.jobs).to be_empty
      end

      it 'does not defer scheduled jobs of a scope with queued jobs' do
        Labkit::Context.with_context(root_namespace: 'group-1') { TestConcurrencyLimitWorker.perform_in(10, 1) }

        expect(TestConcurrencyLimitWorker.jobs.size).to eq(1)
      end

      context 'when the worker is at its limit' do
        before do
          Gitlab::Redis::QueuesMetadata.with do |r|
            5.times { |i| r.hset(executing_key, "p:tid:#{i}", '1|root_namespace:group-3') }
          end
        end

        it 'defers jobs of every scope behind the queued ones' do
          perform_async_for('group-2')

          expect(TestConcurrencyLimitWorker.jobs).to be_empty
        end
      end

      context 'when the scope is not enabled' do
        before do
          allow(worker_class.get_concurrency_limit_scope[:enabled]).to receive(:call).and_return(false)
        end

        it 'defers the job behind the queued ones' do
          perform_async_for('group-2')

          expect(TestConcurrencyLimitWorker.jobs).to be_empty
        end
      end

      context 'when the worker also uses free slots' do
        before do
          stub_feature_flags(sidekiq_concurrency_limit_use_free_slots_TestConcurrencyLimitWorker: true)
        end

        it 'still defers jobs of a scope with queued jobs while the worker is below its limit' do
          expect(service).not_to receive(:free_slot_over_the_limit?)

          perform_async_for('group-1')

          expect(TestConcurrencyLimitWorker.jobs).to be_empty
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

      it 'schedules the job despite queued jobs while the worker is below its limit' do
        defer_job(worker_class.name)
        fill_executing_slots(worker_class.name, 4)

        expect(service).not_to receive(:add_to_queue!)

        TestConcurrencyLimitWorker.perform_async('foo')

        expect(TestConcurrencyLimitWorker.jobs.size).to eq(1)
      end

      it 'defers the job behind queued jobs when the worker is at its limit' do
        defer_job(worker_class.name)
        fill_executing_slots(worker_class.name, 5)

        expect(service).to receive(:add_to_queue!).once

        TestConcurrencyLimitWorker.perform_async('foo')

        expect(TestConcurrencyLimitWorker.jobs).to be_empty
      end

      it 'schedules the job at the limit when no job is queued' do
        fill_executing_slots(worker_class.name, 5)

        TestConcurrencyLimitWorker.perform_async('foo')

        expect(TestConcurrencyLimitWorker.jobs.size).to eq(1)
      end
    end

    context 'when there are jobs in the queue' do
      before do
        allow(::Gitlab::SidekiqMiddleware::ConcurrencyLimit::ConcurrencyLimitService).to receive(:has_jobs_in_queue?)
                                                                                           .and_return(true)
      end

      it 'defers the job' do
        expect(Gitlab::SidekiqMiddleware::ConcurrencyLimit::ConcurrencyLimitService).to receive(:add_to_queue!).once

        TestConcurrencyLimitWorker.perform_async('foo')

        expect(TestConcurrencyLimitWorker.jobs.size).to eq(0)
      end

      it 'does not defer scheduled jobs' do
        expect(Gitlab::SidekiqMiddleware::ConcurrencyLimit::ConcurrencyLimitService).not_to receive(:add_to_queue!)

        TestConcurrencyLimitWorker.perform_in(10, 'foo')
      end
    end
  end
end
