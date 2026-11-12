# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Ci::TimedOutBuilds::DropRunningService, :freeze_time, feature_category: :continuous_integration, factory_default: :keep do
  # Runs before the let_it_be below, so the partition gets id 100, where builds are created by default.
  before_all do
    FactoryBot::Internal.sequences[:ci_partition_id].rewind
  end

  let_it_be(:ci_partition) { create(:ci_partition) }
  let_it_be(:namespace) { create_default(:namespace) }
  let_it_be(:project) { create_default(:project) }
  let_it_be(:runner) { create(:ci_runner) }
  let(:timeout) { 600 }
  # A build is created (queued) before it transitions to running, so
  # ci_builds.created_at is earlier than ci_running_builds.created_at. The
  # timeout is measured from when the build started running, so it must be
  # driven by running_build.created_at, not job.created_at.
  let(:build_created_at) { 1.day.ago }
  let(:running_created_at) { timeout.seconds.ago - described_class::MINUTE_BUFFER - 1.second }
  let!(:job) { create(:ci_build, :running, runner: runner, timeout: timeout, created_at: build_created_at) }
  let!(:running_build) { create(:ci_running_build, runner: runner, build: job, created_at: running_created_at) }

  subject(:service) { described_class.new }

  context 'when job timeout has been exceeded' do
    it_behaves_like 'job is dropped with failure reason', 'server_timeout_running'
    it_behaves_like 'when invalid dooms the job bypassing validations'

    context 'when job becomes complete before processing the timeout' do
      it 'does not doom the job' do
        allow(service).to receive(:drop_build).and_wrap_original do |method, *args|
          job.success
          method.call(*args)
        end

        service.execute
        expect(job.reload.status).to eq("success")
      end
    end

    context 'when the job is complete' do
      before do
        job.success!
      end

      it_behaves_like 'job is unchanged'

      context 'when the runtime_metadata record has not been removed' do
        before do
          create(:ci_running_build, runner: runner, build: job, created_at: running_created_at)
        end

        it_behaves_like 'job is unchanged'
      end
    end

    context 'when the job is not complete' do
      context 'when the status changes to completed on a retry in retry_lock' do
        before do
          allow_next_found_instance_of(Ci::Build) do |build|
            allow(build).to receive(:drop!) do
              raise ActiveRecord::StaleObjectError, "mocked stale"
            end

            allow(build).to receive(:reset) do
              build.success!
            end
          end
        end

        it 'does not doom the job' do
          service.execute
          expect(job.reload).to be_success
        end
      end

      context 'when the status transition fails' do
        before do
          allow_next_found_instance_of(Ci::Build) do |build|
            allow(build).to receive(:drop!).and_raise(StateMachines::InvalidTransition)
          end
        end

        it 'dooms the job' do
          service.execute
          expect(job.reload.status).to eq("failed")
          expect(job.failure_reason).to eq("data_integrity_failure")
        end
      end
    end
  end

  context 'when job timeout has not been exceeded' do
    let(:running_created_at) { timeout.seconds.ago - described_class::MINUTE_BUFFER + 1.second }

    it_behaves_like 'job is unchanged'
  end

  context 'when the run stays within its time budget' do
    it 'drops the timed-out build and reports that it did not run over time', :aggregate_failures do
      expect(service.execute).to be(false)

      expect(job.reload).to be_failed
    end
  end

  context 'when the run spends its time budget' do
    let!(:other_job) { create(:ci_build, :running, runner: runner, timeout: timeout, created_at: build_created_at) }
    let!(:other_running_build) do
      create(:ci_running_build, runner: runner, build: other_job, created_at: running_created_at)
    end

    # A later partition, so the run has a partition left to skip once the budget is spent.
    let_it_be(:later_partition) { create(:ci_partition, id: ci_partition.id + 1) }

    before do
      # Over time as soon as the first build has been dropped, whatever order the batch comes back in.
      allow_next_instance_of(Gitlab::Metrics::RuntimeLimiter) do |limiter|
        allow(limiter).to receive(:over_time?) { Ci::Build.failed.exists? }
        allow(limiter).to receive(:was_over_time?) { Ci::Build.failed.exists? }
      end
    end

    it 'stops after the current build, skips the remaining partitions and reports it ran over time',
      :aggregate_failures do
      expect(service).to receive(:timed_out_builds).once.and_call_original

      expect(service.execute).to be(true)

      expect([job, other_job].map { |build| build.reload.status }).to contain_exactly('failed', 'running')
    end
  end
end
