# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Ci::Runners::RunnerManagerCapService, :freeze_time, feature_category: :runner_core do
  let_it_be(:runner) { create(:ci_runner) }
  let_it_be(:other_runner) { create(:ci_runner) }

  let(:service) { described_class.new }
  let(:cap) { 2 }
  let(:budget) { 1_000 }
  let(:lfk_pending_limit) { 10_000 }
  let(:ceiling) { 0 }

  subject(:response) { service.execute }

  before do
    stub_application_setting(
      ci_max_runner_managers_per_runner: cap,
      ci_runner_manager_cap_deletions_per_run: budget,
      ci_runner_manager_cap_cleanup_backlog_limit: lfk_pending_limit,
      ci_runner_manager_creation_ceiling: ceiling
    )
  end

  def create_manager(target_runner = runner, created_at: 1.minute.ago, contacted_at: created_at)
    create(:ci_runner_machine, runner: target_runner, created_at: created_at, contacted_at: contacted_at)
  end

  context 'when all feature flags are disabled' do
    let(:ceiling) { 3 }

    before do
      stub_feature_flags(
        log_runner_manager_cap: false,
        enforce_runner_manager_cap: false,
        enforce_runner_manager_ceiling: false
      )
      create_list(:ci_runner_machine, 3, runner: runner)
    end

    it 'does nothing' do
      expect { response }.not_to change { Ci::RunnerManager.count }
      expect(response.payload).to eq(skipped: true)
    end
  end

  context 'when the cap and the ceiling are 0' do
    let(:cap) { 0 }

    before do
      create_list(:ci_runner_machine, 3, runner: runner)
    end

    it 'does nothing' do
      expect { response }.not_to change { Ci::RunnerManager.count }
      expect(response.payload).to eq(skipped: true)
    end
  end

  context 'when only the log feature flag is enabled' do
    before do
      stub_feature_flags(enforce_runner_manager_cap: false)
    end

    let!(:managers) { Array.new(3) { create_manager(created_at: 3.days.ago) } << create_manager }

    it 'logs runners over the cap without deleting managers' do
      expect(Gitlab::AppJsonLogger).to receive(:info).with(
        Labkit::Fields::CLASS_NAME => described_class.name,
        message: 'Runner manager cap exceeded',
        runner_id: runner.id,
        runner_type: runner.runner_type,
        runner_managers_count: cap + 1,
        limit: cap,
        enforced: false
      )

      expect { response }.not_to change { Ci::RunnerManager.count }
      expect(response.payload).to include(runners_over_cap: 1, deleted_count: 0)
    end
  end

  context 'when the enforce feature flag is enabled' do
    let!(:stale_manager) { create_manager(created_at: 8.days.ago) }
    let!(:idle_for_two_days) { create_manager(created_at: 9.days.ago, contacted_at: 2.days.ago) }
    let!(:idle_for_three_hours) { create_manager(created_at: 9.days.ago, contacted_at: 3.hours.ago) }
    let!(:active_manager) { create_manager(created_at: 9.days.ago, contacted_at: 10.minutes.ago) }
    let!(:new_manager) { create_manager }
    let!(:other_runner_manager) { create_manager(other_runner, created_at: 8.days.ago) }

    it 'deletes long-idle managers down to the cap' do
      expect { response }.to change { Ci::RunnerManager.count }.by(-3)

      expect(Ci::RunnerManager.all).to contain_exactly(active_manager, new_manager, other_runner_manager)
      expect(response.payload).to include(runners_over_cap: 1, deleted_count: 3, discovery_limit_reached: false)
    end

    context 'when a runner that created managers recently is under the cap' do
      before do
        create_manager(other_runner)
      end

      it 'only trims the runner over the cap' do
        expect { response }.to change { Ci::RunnerManager.count }.by(-3)
        expect(response.payload).to include(runners_over_cap: 1)
      end
    end

    context 'when the runner is deleted after its managers are counted' do
      before do
        allow(Ci::RunnerManager).to receive(:count_for_runner_key).and_wrap_original do |method, *args, **kwargs|
          method.call(*args, **kwargs).tap { Ci::Runner.id_in(runner.id).delete_all }
        end
      end

      it 'skips it' do
        expect(response.payload).to include(runners_over_cap: 0, deleted_count: 0)
      end
    end

    context 'when discovery reaches MAX_RUNNERS_PER_RUN' do
      before do
        stub_const("#{described_class}::MAX_RUNNERS_PER_RUN", 1)
      end

      it 'reports it' do
        expect(response.payload).to include(discovery_limit_reached: true)
      end
    end

    it 'logs the runner as enforced' do
      allow(Gitlab::AppJsonLogger).to receive(:info)

      response

      expect(Gitlab::AppJsonLogger).to have_received(:info).with(hash_including(runner_id: runner.id, enforced: true))
    end

    context 'when the managers over the cap are all inside the grace period' do
      let(:cap) { 1 }

      before do
        [stale_manager, idle_for_two_days, idle_for_three_hours].each(&:delete)
      end

      it 'does not delete them' do
        expect { response }.not_to change { Ci::RunnerManager.count }
      end
    end

    context 'when a manager contacted_at is past the online timeout but within the contact update lag' do
      let(:cap) { 1 }

      before do
        [stale_manager, idle_for_two_days, idle_for_three_hours].each(&:delete)
        create_manager(created_at: 9.days.ago, contacted_at: 150.minutes.ago)
      end

      it 'does not delete it' do
        expect { response }.not_to change { Ci::RunnerManager.count }
      end
    end

    context 'when the runner has not created managers recently' do
      before do
        new_manager.update!(created_at: 1.hour.ago)
      end

      it 'does not look at the runner' do
        expect { response }.not_to change { Ci::RunnerManager.count }
        expect(response.payload).to include(runners_over_cap: 0)
      end
    end

    context 'when the enforce feature flag is enabled for another runner only' do
      before do
        stub_feature_flags(enforce_runner_manager_cap: other_runner)
      end

      it 'does not delete managers' do
        expect { response }.not_to change { Ci::RunnerManager.count }
      end
    end

    context 'when the deletion budget is smaller than the excess' do
      let(:budget) { 2 }

      it 'stops at the budget' do
        expect { response }.to change { Ci::RunnerManager.count }.by(-2)

        expect(Ci::RunnerManager.all).not_to include(stale_manager, idle_for_two_days)
        expect(response.payload).to include(deleted_count: 2, stop_reason: :budget)
      end
    end

    context 'when the budget runs out before the next runner over the cap' do
      let(:budget) { 1 }

      before do
        3.times { create_manager(other_runner, created_at: 8.days.ago) }
        create_manager(other_runner)
      end

      it 'does not trim the next runner' do
        allow(Gitlab::AppJsonLogger).to receive(:info)

        expect { response }.to change { Ci::RunnerManager.count }.by(-1)
        expect(response.payload).to include(runners_over_cap: 2, deleted_count: 1, stop_reason: :budget)
        # The order of the two runners isn't fixed, so only the trimmed one is logged as enforced.
        expect(Gitlab::AppJsonLogger).to have_received(:info).with(hash_including(enforced: true)).once
        expect(Gitlab::AppJsonLogger).to have_received(:info).with(hash_including(enforced: false)).once
      end
    end

    context 'with more deletions than SUB_BATCH_SIZE' do
      before do
        stub_const("#{described_class}::SUB_BATCH_SIZE", 1)
      end

      it 'deletes in sub-batches' do
        expect { response }.to change { Ci::RunnerManager.count }.by(-3)
      end
    end

    context 'when loose foreign key cleanup is behind' do
      before do
        allow_next_instance_of(Ci::Runners::LooseForeignKeysBacklog) do |backlog|
          allow(backlog).to receive(:over_limit?).with(lfk_pending_limit).and_return(true)
        end
      end

      it 'does not delete managers' do
        expect { response }.not_to change { Ci::RunnerManager.count }
        expect(response.payload).to include(deleted_count: 0, stop_reason: :loose_foreign_keys)
      end
    end

    context 'when loose foreign key cleanup catches up during the run' do
      before do
        3.times { create_manager(other_runner, created_at: 8.days.ago) }
        create_manager(other_runner)

        allow_next_instance_of(Ci::Runners::LooseForeignKeysBacklog) do |backlog|
          allow(backlog).to receive(:over_limit?).with(lfk_pending_limit).and_return(true, false)
        end
      end

      it 'does not restart deletions' do
        expect { response }.not_to change { Ci::RunnerManager.count }
        expect(response.payload).to include(runners_over_cap: 2, stop_reason: :loose_foreign_keys)
      end
    end

    context 'when the run takes too long while counting' do
      before do
        allow_next_instance_of(Gitlab::Metrics::RuntimeLimiter) do |limiter|
          allow(limiter).to receive(:over_time?).and_return(true)
        end
      end

      it 'stops before counting or deleting' do
        expect { response }.not_to change { Ci::RunnerManager.count }
        expect(response.payload).to include(runners_over_cap: 0, stop_reason: :runtime)
      end
    end

    context 'when the run takes too long while deleting' do
      before do
        allow_next_instance_of(Gitlab::Metrics::RuntimeLimiter) do |limiter|
          # The first check is while counting the only discovered runner, the next ones are before deleting.
          allow(limiter).to receive(:over_time?).and_return(false, true)
        end
      end

      it 'stops before deleting' do
        expect { response }.not_to change { Ci::RunnerManager.count }
        expect(response.payload).to include(runners_over_cap: 1, stop_reason: :runtime)
      end
    end

    it 'reports the loose foreign key backlog' do
      allow_next_instance_of(Ci::Runners::LooseForeignKeysBacklog) do |backlog|
        allow(backlog).to receive(:pending_count).and_call_original
        allow(backlog).to receive(:pending_count).with(limit: lfk_pending_limit * 10).and_return(42)
      end

      expect(response.payload).to include(lfk_pending_records: 42)
    end

    it 'leaves out the loose foreign key backlog when counting it times out' do
      allow_next_instance_of(Ci::Runners::LooseForeignKeysBacklog) do |backlog|
        allow(backlog).to receive(:pending_count).and_call_original
        allow(backlog).to receive(:pending_count).with(limit: lfk_pending_limit * 10)
          .and_raise(ActiveRecord::QueryCanceled)
      end

      expect(response.payload).to include(deleted_count: 3)
      expect(response.payload).not_to have_key(:lfk_pending_records)
    end
  end

  context 'with the creation ceiling', :clean_gitlab_redis_shared_state do
    let(:ceiling) { 3 }
    let(:ceiling_set) { Ci::Runners::RunnerManagerCreationCeiling }

    before do
      allow(Gitlab::AppJsonLogger).to receive(:info)
    end

    context 'when a runner reaches the ceiling' do
      before do
        create_list(:ci_runner_machine, 3, runner: runner, created_at: 1.minute.ago, contacted_at: 1.minute.ago)
        create_manager(other_runner)
      end

      it 'records and logs the runner' do
        expect(response.payload).to include(runners_at_ceiling: 1)

        expect(ceiling_set.reached?(runner)).to be(true)
        expect(ceiling_set.reached?(other_runner)).to be(false)
        expect(Gitlab::AppJsonLogger).to have_received(:info).with(
          Labkit::Fields::CLASS_NAME => described_class.name,
          message: 'Runner manager creation ceiling reached',
          runner_id: runner.id,
          runner_managers_count: 3,
          limit: ceiling,
          trimming_paused: false
        )
      end

      context 'when loose foreign key cleanup is behind' do
        before do
          allow_next_instance_of(Ci::Runners::LooseForeignKeysBacklog) do |backlog|
            allow(backlog).to receive_messages(pending_count: lfk_pending_limit + 1, over_limit?: true)
          end
        end

        it 'still records the runner and logs that trimming is paused' do
          response

          expect(ceiling_set.reached?(runner)).to be(true)
          expect(Gitlab::AppJsonLogger).to have_received(:info)
            .with(hash_including(message: 'Runner manager creation ceiling reached', trimming_paused: true))
        end
      end

      context 'when counting the loose foreign key backlog for the log times out' do
        before do
          allow_next_instance_of(Ci::Runners::LooseForeignKeysBacklog) do |backlog|
            allow(backlog).to receive(:pending_count).and_raise(ActiveRecord::QueryCanceled)
            allow(backlog).to receive(:over_limit?).with(lfk_pending_limit).and_return(over_limit)
          end
        end

        context 'when the backlog is over the limit' do
          let(:over_limit) { true }

          it 'logs that trimming is paused' do
            response

            expect(Gitlab::AppJsonLogger).to have_received(:info)
              .with(hash_including(message: 'Runner manager creation ceiling reached', trimming_paused: true))
          end
        end

        context 'when the backlog is within the limit' do
          let(:over_limit) { false }

          it 'logs that trimming is not paused' do
            response

            expect(Gitlab::AppJsonLogger).to have_received(:info)
              .with(hash_including(message: 'Runner manager creation ceiling reached', trimming_paused: false))
          end
        end
      end

      context 'when only the ceiling enforce feature flag is enabled' do
        before do
          stub_feature_flags(log_runner_manager_cap: false, enforce_runner_manager_cap: false)
        end

        it 'records the runner without checking the cap' do
          expect { response }.not_to change { Ci::RunnerManager.count }

          expect(ceiling_set.reached?(runner)).to be(true)
          expect(response.payload).to include(runners_over_cap: 0)
          expect(Gitlab::AppJsonLogger).not_to have_received(:info)
            .with(hash_including(message: 'Runner manager cap exceeded'))
        end
      end

      context 'when only the cap enforce feature flag is enabled' do
        before do
          stub_feature_flags(log_runner_manager_cap: false, enforce_runner_manager_ceiling: false)
        end

        it 'checks the cap without recording the runner' do
          expect(ceiling_set).not_to receive(:record)

          expect(response.payload).to include(runners_over_cap: 1, runners_at_ceiling: 0)
        end
      end

      context 'when the cap is 0' do
        let(:cap) { 0 }

        it 'records the runner without deleting managers' do
          expect { response }.not_to change { Ci::RunnerManager.count }

          expect(ceiling_set.reached?(runner)).to be(true)
          expect(response.payload).to include(runners_over_cap: 0)
        end
      end
    end

    context 'when a recorded runner has not created managers recently' do
      before do
        create_list(:ci_runner_machine, 3, runner: runner, created_at: 1.hour.ago, contacted_at: 1.hour.ago)
        ceiling_set.record(reached_runner_ids: [runner.id], cleared_runner_ids: [])
      end

      it 'counts the runner again and renews its entry' do
        expect(ceiling_set).to receive(:record)
          .with(reached_runner_ids: [runner.id], cleared_runner_ids: []).and_call_original

        expect(response.payload).to include(runners_at_ceiling: 1)
      end

      context 'when the run takes too long after counting one runner' do
        before do
          create_manager(other_runner)
          allow_next_instance_of(Gitlab::Metrics::RuntimeLimiter) do |limiter|
            allow(limiter).to receive(:over_time?).and_return(false, true)
          end
        end

        it 'counts the recorded runner first' do
          expect(ceiling_set).to receive(:record)
            .with(reached_runner_ids: [runner.id], cleared_runner_ids: []).and_call_original

          expect(response.payload).to include(runners_at_ceiling: 1, stop_reason: :runtime)
        end
      end

      context 'when it has dropped below the ceiling' do
        before do
          Ci::RunnerManager.for_runner(runner).first.delete
        end

        it 'clears the runner' do
          response

          expect(ceiling_set.reached?(runner)).to be(false)
        end
      end
    end

    context 'when a recorded runner also created managers recently' do
      before do
        create_list(:ci_runner_machine, 3, runner: runner, created_at: 1.minute.ago, contacted_at: 1.minute.ago)
        ceiling_set.record(reached_runner_ids: [runner.id], cleared_runner_ids: [])
      end

      it 'counts it once' do
        allow(Ci::RunnerManager).to receive(:count_for_runner_key).and_call_original
        expect(Ci::RunnerManager).to receive(:count_for_runner_key)
          .with(runner.id, runner.runner_type, limit: ceiling + 1).once.and_call_original

        expect(response.payload).to include(runners_at_ceiling: 1)
      end
    end

    context 'when Redis is unavailable' do
      before do
        3.times { create_manager(created_at: 3.days.ago) }
        create_manager
        allow(Gitlab::Redis::SharedState).to receive(:with).and_raise(::Redis::CannotConnectError)
        allow(Gitlab::ErrorTracking).to receive(:track_and_raise_for_dev_exception)
      end

      it 'still trims runners over the cap' do
        expect { response }.to change { Ci::RunnerManager.count }.by(-2)
        expect(Gitlab::ErrorTracking).to have_received(:track_and_raise_for_dev_exception).twice
      end
    end

    context 'when the ceiling is 0' do
      let(:ceiling) { 0 }

      before do
        create_list(:ci_runner_machine, 3, runner: runner, created_at: 1.minute.ago, contacted_at: 1.minute.ago)
      end

      it 'does not record runners' do
        expect(ceiling_set).not_to receive(:record)

        response
      end
    end
  end
end
