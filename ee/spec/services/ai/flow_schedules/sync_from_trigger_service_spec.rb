# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Ai::FlowSchedules::SyncFromTriggerService, feature_category: :dap_triggers do
  include ExclusiveLeaseHelpers

  let_it_be_with_reload(:project) { create(:project, :in_group) }

  let(:schedule_config) do
    { 'frequency' => 'DAILY', 'minute' => 30, 'hour' => 14, 'timezone' => 'America/New_York' }
  end

  let(:trigger) do
    create(:ai_flow_trigger, :autonomous,
      project: project,
      filter: { 'scheduled' => schedule_config })
  end

  let(:service) { described_class.new(trigger: trigger) }

  subject(:execute) { service.execute }

  include_context 'with scheduled triggers available'

  describe '#execute' do
    context 'when the trigger is nil' do
      let(:service) { described_class.new(trigger: nil) }

      it 'succeeds without creating schedules' do
        expect { execute }.not_to change { Ai::FlowSchedule.count }
        expect(execute).to be_success
      end
    end

    context 'when the ai_flow_schedules feature flag is disabled' do
      before do
        stub_feature_flags(ai_flow_schedules: false)
      end

      it 'succeeds without creating schedules' do
        expect { execute }.not_to change { Ai::FlowSchedule.count }
        expect(execute).to be_success
      end

      context 'when the trigger still has the scheduled event type' do
        let!(:existing_schedule) { create(:ai_flow_schedule, flow_trigger: trigger, project: project) }

        before do
          trigger.update!(description: 'touched')
        end

        it 'leaves the live schedule alone', :aggregate_failures do
          expect { execute }.not_to change { Ai::FlowSchedule.count }

          expect(execute).to be_success
          expect(existing_schedule.reload).to be_persisted
        end
      end

      context 'when the scheduled event type has been dropped' do
        let!(:existing_schedule) { create(:ai_flow_schedule, flow_trigger: trigger, project: project) }

        before do
          trigger.update!(
            event_types: [::Ai::FlowTrigger::EVENT_TYPES[:mention]],
            filter: {},
            autonomous_service_account: nil
          )
        end

        it 'removes the schedules anyway', :aggregate_failures do
          expect { execute }.to change { Ai::FlowSchedule.count }.by(-1)

          expect(execute).to be_success
          expect(Ai::FlowSchedule.find_by_id(existing_schedule.id)).to be_nil
        end
      end
    end

    context 'when the exclusive lock is already held' do
      before do
        stub_exclusive_lease_taken("ai_flow_schedules:sync_from_trigger:#{trigger.id}")
      end

      it 'returns an error without creating a schedule' do
        expect { execute }.not_to change { Ai::FlowSchedule.count }

        expect(execute).to be_error
        expect(execute.message).to eq('Could not acquire lock to sync flow schedule')
      end
    end

    context 'when the trigger has the scheduled event type and schedule config' do
      it 'creates a schedule from the config' do
        expect { execute }.to change { Ai::FlowSchedule.count }.by(1)

        expect(execute).to be_success

        schedule = execute.payload[:flow_schedule]
        expect(schedule).to have_attributes(
          project_id: project.id,
          ai_flow_trigger_id: trigger.id,
          cron: '30 14 * * *',
          cron_timezone: 'America/New_York',
          description: trigger.description,
          active: true
        )
        expect(schedule.next_run_at).to be_present
      end

      context 'when scheduled triggers are turned off for the project' do
        before do
          trigger
          project.project_setting.update!(duo_scheduled_triggers_enabled: false)
        end

        it 'does not build a schedule' do
          expect { execute }.not_to change { Ai::FlowSchedule.count }

          expect(execute).to be_success
          expect(execute.payload[:flow_schedule]).to be_nil
        end

        it 'leaves the trigger save unaffected' do
          expect(execute).to be_success
        end

        context 'when the trigger already has a schedule' do
          let!(:existing_schedule) do
            create(:ai_flow_schedule, flow_trigger: trigger, cron: '0 9 * * 1', cron_timezone: 'UTC')
          end

          it 'still updates it, so the trigger stays editable' do
            expect { execute }.not_to change { Ai::FlowSchedule.count }

            expect(execute).to be_success
            expect(existing_schedule.reload).to have_attributes(
              cron: '30 14 * * *',
              cron_timezone: 'America/New_York'
            )
          end
        end
      end

      context 'when experiment and beta features are turned off' do
        before do
          trigger
          stub_application_setting(instance_level_ai_beta_features_enabled: false)
        end

        it 'does not build a schedule' do
          expect { execute }.not_to change { Ai::FlowSchedule.count }

          expect(execute).to be_success
          expect(execute.payload[:flow_schedule]).to be_nil
        end

        context 'when the trigger already has a schedule' do
          let!(:existing_schedule) do
            create(:ai_flow_schedule, flow_trigger: trigger, cron: '0 9 * * 1', cron_timezone: 'UTC')
          end

          it 'still updates it, so the trigger stays editable' do
            expect { execute }.not_to change { Ai::FlowSchedule.count }

            expect(execute).to be_success
            expect(existing_schedule.reload).to have_attributes(
              cron: '30 14 * * *',
              cron_timezone: 'America/New_York'
            )
          end
        end
      end

      context 'when the trigger already has a schedule' do
        let!(:existing_schedule) do
          create(:ai_flow_schedule, flow_trigger: trigger, cron: '0 9 * * 1', cron_timezone: 'UTC')
        end

        it 'updates the existing schedule instead of creating a new one' do
          expect { execute }.not_to change { Ai::FlowSchedule.count }

          expect(execute).to be_success
          expect(existing_schedule.reload).to have_attributes(
            cron: '30 14 * * *',
            cron_timezone: 'America/New_York'
          )
        end

        it 'recalculates next_run_at for the new cron' do
          expect { execute }.to change { existing_schedule.reload.next_run_at }
        end

        context 'when the schedule config is unchanged' do
          let!(:existing_schedule) do
            create(:ai_flow_schedule, flow_trigger: trigger, cron: '30 14 * * *',
              cron_timezone: 'America/New_York')
          end

          it 'preserves next_run_at' do
            expect { execute }.not_to change { existing_schedule.reload.next_run_at }
          end
        end
      end

      context 'when the existing schedule is inactive' do
        let(:schedule_traits) { [:deactivated_by_failures] }
        let!(:existing_schedule) { create(:ai_flow_schedule, *schedule_traits, flow_trigger: trigger) }

        it 'reactivates a schedule deactivated by failures and resets its failure count' do
          execute

          expect(existing_schedule.reload).to have_attributes(active: true, consecutive_failure_count: 0)
        end

        context 'when the saved trigger is inactive' do
          before do
            trigger.update_column(:active, false)
            trigger.active = true
          end

          it 'keeps the schedule inactive' do
            expect { execute }.not_to change { existing_schedule.reload.active }.from(false)
          end
        end

        context 'when the schedule was not deactivated by failures' do
          let(:schedule_traits) { [] }

          before do
            existing_schedule.deactivate!
          end

          it 'keeps the schedule inactive' do
            expect { execute }.not_to change { existing_schedule.reload.active }.from(false)
          end
        end
      end

      context 'when the schedule config is invalid' do
        before do
          # The trigger JSON schema rejects unknown frequencies, so bypass
          # validation to cover rows written before the schema existed.
          trigger.update_column(:filter, { 'scheduled' => { 'frequency' => 'SOMETIMES' } })
        end

        it 'returns the converter error' do
          expect { execute }.not_to change { Ai::FlowSchedule.count }

          expect(execute).to be_error
          expect(execute.message).to include('Unknown schedule frequency: SOMETIMES')
        end
      end

      context 'when the schedule cannot be saved' do
        before do
          create(:plan_limits, :default_plan, ai_flow_schedules: 1)
          other_trigger = create(:ai_flow_trigger, :autonomous, project: project)
          create(:ai_flow_schedule, flow_trigger: other_trigger)
        end

        it 'returns the validation error' do
          expect { execute }.not_to change { Ai::FlowSchedule.count }

          expect(execute).to be_error
          expect(execute.message).to include('Maximum number of ai flow schedules (1) exceeded')
        end
      end
    end

    context 'when the trigger has the scheduled event type but no schedule config' do
      let(:trigger) do
        create(:ai_flow_trigger, :autonomous,
          project: project,
          filter: {})
      end

      it 'succeeds without creating or removing schedules' do
        existing_schedule = create(:ai_flow_schedule, flow_trigger: trigger)

        expect { execute }.not_to change { Ai::FlowSchedule.count }

        expect(execute).to be_success
        expect(existing_schedule.reload).to be_persisted
      end
    end

    context 'when the trigger does not have the scheduled event type' do
      it 'removes existing schedules' do
        create(:ai_flow_schedule, flow_trigger: trigger)
        trigger.update!(
          event_types: [Ai::FlowTrigger::EVENT_TYPES[:mention]], filter: {}, autonomous_service_account: nil
        )

        expect { execute }.to change { Ai::FlowSchedule.count }.by(-1)
        expect(execute).to be_success
      end

      it 'succeeds when there is nothing to remove' do
        trigger.update!(
          event_types: [Ai::FlowTrigger::EVENT_TYPES[:mention]], filter: {}, autonomous_service_account: nil
        )

        expect { execute }.not_to change { Ai::FlowSchedule.count }
        expect(execute).to be_success
      end
    end
  end
end
