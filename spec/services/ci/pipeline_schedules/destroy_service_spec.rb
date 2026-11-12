# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Ci::PipelineSchedules::DestroyService, feature_category: :continuous_integration do
  let_it_be(:user) { create(:user) }
  let_it_be(:owner) { create(:user) }
  let_it_be(:developer) { create(:user) }
  let_it_be(:project) do
    create(:project, :public, maintainers: [user, owner], developers: developer)
  end

  let_it_be_with_refind(:pipeline_schedule) { create(:ci_pipeline_schedule, project: project, owner: owner) }

  describe '#execute' do
    context 'when the user cannot administer the schedule' do
      subject(:service) { described_class.new(pipeline_schedule, developer) }

      it 'returns a forbidden error and keeps the schedule', :aggregate_failures do
        result = service.execute

        expect(result).to be_error
        expect(result.reason).to eq(:forbidden)
        expect(result.message).to eq(_('The current user is not authorized to delete the pipeline schedule'))
        expect(result.payload).to eq(pipeline_schedule)
        expect(Ci::PipelineSchedule.exists?(pipeline_schedule.id)).to be(true)
      end
    end

    context 'when the user can administer the schedule' do
      subject(:service) { described_class.new(pipeline_schedule, user) }

      before do
        create(:ci_pipeline_schedule_variable, pipeline_schedule: pipeline_schedule)
        create(:ci_pipeline_schedule_input, pipeline_schedule: pipeline_schedule)
      end

      it 'destroys the schedule with its variables and inputs', :aggregate_failures do
        result = service.execute

        expect(result).to be_success
        expect(result.payload).to eq(pipeline_schedule)
        expect(Ci::PipelineSchedule.exists?(pipeline_schedule.id)).to be(false)
        expect(Ci::PipelineScheduleVariable.where(pipeline_schedule_id: pipeline_schedule.id)).to be_empty
        expect(Ci::PipelineScheduleInput.where(pipeline_schedule_id: pipeline_schedule.id)).to be_empty
      end

      context 'when the schedule cannot be destroyed' do
        before do
          allow(pipeline_schedule).to receive(:destroy).and_return(false)
        end

        it 'returns an error with the schedule as payload', :aggregate_failures do
          result = service.execute

          expect(result).to be_error
          expect(result.reason).to be_nil
          expect(result.message).to eq(_('Failed to remove the pipeline schedule'))
          expect(result.payload).to eq(pipeline_schedule)
        end
      end
    end

    context 'with rate limiting', :clean_gitlab_redis_rate_limiting, :freeze_time do
      let(:unauthorized_user) { developer }

      def grant_access(member)
        project.add_maintainer(member)
      end

      def execute_service(actor = user, target_project = project)
        schedule = create(:ci_pipeline_schedule, project: target_project, owner: owner)

        described_class.new(schedule, actor).execute
      end

      it_behaves_like 'a rate limited pipeline schedule management action'

      context 'when the rate limit is reached' do
        let(:schedule) { create(:ci_pipeline_schedule, project: project, owner: owner) }

        before do
          stub_application_setting(pipeline_schedule_management_limit_per_user: 1)
        end

        it 'keeps the schedule once the allowance is spent' do
          execute_service

          described_class.new(schedule, user).execute

          expect(Ci::PipelineSchedule.exists?(schedule.id)).to be(true)
        end

        it 'shares the allowance with creating a schedule', :aggregate_failures do
          create_response = Ci::PipelineSchedules::CreateService.new(project, user,
            { description: 'desc', ref: 'refs/heads/master', cron: '*/1 * * * *', cron_timezone: 'UTC' }).execute
          expect(create_response).to be_success

          expect(execute_service.reason).to eq(:rate_limited)
        end
      end
    end
  end
end
