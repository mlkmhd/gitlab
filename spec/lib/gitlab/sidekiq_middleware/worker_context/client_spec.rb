# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Gitlab::SidekiqMiddleware::WorkerContext::Client do
  let(:worker_class) do
    Class.new do
      def self.name
        'TestWithContextWorker'
      end

      include ApplicationWorker

      feature_category :team_planning

      def self.job_for_args(args)
        jobs.find { |job| job['args'] == args }
      end

      def perform(*args); end
    end
  end

  let(:not_owned_worker_class) do
    Class.new(worker_class) do
      def self.name
        'TestNotOwnedWithContextWorker'
      end

      feature_category :not_owned
    end
  end

  let(:mailer_class) do
    Class.new(ApplicationMailer) do
      def self.name
        'TestMailer'
      end

      def test_mail; end
    end
  end

  before do
    stub_const(worker_class.name, worker_class)
    stub_const(not_owned_worker_class.name, not_owned_worker_class)
    stub_const(mailer_class.name, mailer_class)
  end

  describe "#call" do
    context 'root_caller_id' do
      it 'uses caller_id of the current context' do
        Gitlab::ApplicationContext.with_context(caller_id: 'CALLER') do
          TestWithContextWorker.perform_async
        end

        job = TestWithContextWorker.jobs.last
        expect(job['meta.root_caller_id']).to eq('CALLER')
      end

      it 'uses root_caller_id instead of caller_id of the current context' do
        Gitlab::ApplicationContext.with_context(caller_id: 'CALLER', root_caller_id: 'ROOT_CALLER') do
          TestWithContextWorker.perform_async
        end

        job = TestWithContextWorker.jobs.last
        expect(job['meta.root_caller_id']).to eq('ROOT_CALLER')
      end
    end

    context 'root_started_at' do
      it 'uses root_started_at of the current context' do
        Gitlab::ApplicationContext.with_context(root_started_at: 1234.5) do
          TestWithContextWorker.perform_async
        end

        job = TestWithContextWorker.jobs.last
        expect(job['meta.root_started_at']).to eq(1234.5)
      end

      it 'uses the request start time when enqueued during a request', :request_store do
        Gitlab::RequestContext.instance.request_start_time = 1234.5

        TestWithContextWorker.perform_async

        job = TestWithContextWorker.jobs.last
        expect(job['meta.root_started_at']).to eq(1234.5)
      end

      it 'uses the current time when enqueued outside a request' do
        freeze_time do
          TestWithContextWorker.perform_async

          job = TestWithContextWorker.jobs.last
          expect(job['meta.root_started_at']).to eq(Time.now.utc.to_f)
        end
      end

      context 'when the log_correlation_duration feature flag is disabled' do
        before do
          stub_feature_flags(log_correlation_duration: false)
        end

        it 'does not start a new chain' do
          TestWithContextWorker.perform_async

          job = TestWithContextWorker.jobs.last
          expect(job).not_to have_key('meta.root_started_at')
        end
      end
    end

    context 'correlation_depth' do
      it 'is one deeper than the job of the current context' do
        Gitlab::ApplicationContext.with_context(correlation_depth: 3) do
          TestWithContextWorker.perform_async
        end

        job = TestWithContextWorker.jobs.last
        expect(job['meta.correlation_depth']).to eq(4)
      end

      it 'starts a chain at depth 1 when enqueued outside a job' do
        TestWithContextWorker.perform_async

        job = TestWithContextWorker.jobs.last
        expect(job['meta.correlation_depth']).to eq(1)
      end

      context 'when the log_correlation_duration feature flag is disabled' do
        before do
          stub_feature_flags(log_correlation_duration: false)
        end

        it 'does not set the depth' do
          TestWithContextWorker.perform_async

          job = TestWithContextWorker.jobs.last
          expect(job).not_to have_key('meta.correlation_depth')
        end
      end
    end

    context 'when the job hash already carries its chain, like a retried or scheduled job' do
      let(:job) do
        {
          'class' => TestWithContextWorker,
          'args' => [],
          'meta.root_started_at' => 1234.5,
          'meta.correlation_depth' => 3
        }
      end

      it 'keeps root_started_at and correlation_depth of the job when pushed outside a job' do
        Sidekiq::Client.push(job)

        pushed = TestWithContextWorker.jobs.last
        expect(pushed['meta.root_started_at']).to eq(1234.5)
        expect(pushed['meta.correlation_depth']).to eq(3)
      end

      it 'keeps root_started_at and correlation_depth of the job when pushed from another job' do
        Gitlab::ApplicationContext.with_context(root_started_at: 99.5, correlation_depth: 7) do
          Sidekiq::Client.push(job)
        end

        pushed = TestWithContextWorker.jobs.last
        expect(pushed['meta.root_started_at']).to eq(1234.5)
        expect(pushed['meta.correlation_depth']).to eq(3)
      end

      it 'derives both again when the carried values are not valid' do
        job.merge!('meta.root_started_at' => '2019-06-01T00:00:00Z', 'meta.correlation_depth' => 0)

        Gitlab::ApplicationContext.with_context(root_started_at: 99.5, correlation_depth: 7) do
          Sidekiq::Client.push(job)
        end

        pushed = TestWithContextWorker.jobs.last
        expect(pushed['meta.root_started_at']).to eq(99.5)
        expect(pushed['meta.correlation_depth']).to eq(8)
      end

      context 'when the log_correlation_duration feature flag is disabled' do
        before do
          stub_feature_flags(log_correlation_duration: false)
        end

        it 'drops both from the job and does not inherit them from the context' do
          Gitlab::ApplicationContext.with_context(root_started_at: 99.5, correlation_depth: 7) do
            Sidekiq::Client.push(job)
          end

          pushed = TestWithContextWorker.jobs.last
          expect(pushed).not_to have_key('meta.root_started_at')
          expect(pushed).not_to have_key('meta.correlation_depth')
        end
      end
    end

    it 'applies a context for jobs scheduled in batch' do
      user_per_job = { 'job1' => build_stubbed(:user, username: 'user-1'),
                       'job2' => build_stubbed(:user, username: 'user-2') }

      TestWithContextWorker.bulk_perform_async_with_contexts(
        %w[job1 job2],
        arguments_proc: ->(name) { [name, 1, 2, 3] },
        context_proc: ->(name) { { user: user_per_job[name] } }
      )

      job1 = TestWithContextWorker.job_for_args(['job1', 1, 2, 3])
      job2 = TestWithContextWorker.job_for_args(['job2', 1, 2, 3])

      expect(job1['meta.user']).to eq(user_per_job['job1'].username)
      expect(job2['meta.user']).to eq(user_per_job['job2'].username)
    end

    context 'when the feature category is set in the context_proc' do
      it 'takes the feature category from the worker, not the caller' do
        TestWithContextWorker.bulk_perform_async_with_contexts(
          %w[job1 job2],
          arguments_proc: ->(name) { [name, 1, 2, 3] },
          context_proc: ->(_) { { feature_category: 'code_review' } }
        )

        job1 = TestWithContextWorker.job_for_args(['job1', 1, 2, 3])
        job2 = TestWithContextWorker.job_for_args(['job2', 1, 2, 3])

        expect(job1['meta.feature_category']).to eq('team_planning')
        expect(job2['meta.feature_category']).to eq('team_planning')
      end

      it 'takes the feature category from the caller if the worker is not owned' do
        TestNotOwnedWithContextWorker.bulk_perform_async_with_contexts(
          %w[job1 job2],
          arguments_proc: ->(name) { [name, 1, 2, 3] },
          context_proc: ->(_) { { feature_category: 'code_review' } }
        )

        job1 = TestNotOwnedWithContextWorker.job_for_args(['job1', 1, 2, 3])
        job2 = TestNotOwnedWithContextWorker.job_for_args(['job2', 1, 2, 3])

        expect(job1['meta.feature_category']).to eq('code_review')
        expect(job2['meta.feature_category']).to eq('code_review')
      end

      it 'does not set any explicit feature category for mailers', :sidekiq_mailers do
        expect(Gitlab::ApplicationContext).to receive(:with_context).with(hash_excluding(feature_category: anything))

        TestMailer.test_mail.deliver_later
      end
    end

    context 'when the feature category is already set in the surrounding block' do
      it 'takes the feature category from the worker, not the caller' do
        Gitlab::ApplicationContext.with_context(feature_category: 'system_access') do
          TestWithContextWorker.bulk_perform_async_with_contexts(
            %w[job1 job2],
            arguments_proc: ->(name) { [name, 1, 2, 3] },
            context_proc: ->(_) { {} }
          )
        end

        job1 = TestWithContextWorker.job_for_args(['job1', 1, 2, 3])
        job2 = TestWithContextWorker.job_for_args(['job2', 1, 2, 3])

        expect(job1['meta.feature_category']).to eq('team_planning')
        expect(job2['meta.feature_category']).to eq('team_planning')
      end

      it 'takes the feature category from the caller if the worker is not owned' do
        Gitlab::ApplicationContext.with_context(feature_category: 'system_access') do
          TestNotOwnedWithContextWorker.bulk_perform_async_with_contexts(
            %w[job1 job2],
            arguments_proc: ->(name) { [name, 1, 2, 3] },
            context_proc: ->(_) { {} }
          )
        end

        job1 = TestNotOwnedWithContextWorker.job_for_args(['job1', 1, 2, 3])
        job2 = TestNotOwnedWithContextWorker.job_for_args(['job2', 1, 2, 3])

        expect(job1['meta.feature_category']).to eq('system_access')
        expect(job2['meta.feature_category']).to eq('system_access')
      end
    end
  end
end
