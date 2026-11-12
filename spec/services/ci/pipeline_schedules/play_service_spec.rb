# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Ci::PipelineSchedules::PlayService, :clean_gitlab_redis_rate_limiting, :clean_gitlab_redis_queues,
  feature_category: :continuous_integration do
  let_it_be(:user) { create(:user) }
  let_it_be(:project, freeze: false) { create(:project) }

  let(:service) { described_class.new(project, user) }

  describe '#execute' do
    subject(:execute_service) { service.execute(schedule) }

    let_it_be(:schedule) { create(:ci_pipeline_schedule, project: project, owner: user) }

    context 'when user can play the schedule' do
      before do
        allow(service).to receive(:can?).with(user, :play_pipeline_schedule, schedule).and_return(true)
      end

      it 'does not schedule next run' do
        expect(schedule).not_to receive(:schedule_next_run!)

        execute_service
      end

      it 'runs RunPipelineScheduleWorker' do
        expect(RunPipelineScheduleWorker)
          .to receive(:perform_async).with(schedule.id, schedule.owner.id)

        execute_service
      end

      it 'returns a success response with the job id', :aggregate_failures do
        response = execute_service

        expect(response).to be_success
        expect(response.payload[:job_id]).to be_present
      end

      context 'when the worker is not enqueued' do
        before do
          allow(RunPipelineScheduleWorker).to receive(:perform_async).and_return(nil)
        end

        it 'returns an error response', :aggregate_failures do
          response = execute_service

          expect(response).to be_error
          expect(response.reason).to be_nil
          expect(response.message).to eq('Unable to schedule a pipeline to run immediately.')
        end
      end

      context 'when owner is nil' do
        let(:schedule) { create(:ci_pipeline_schedule, project: project, owner: nil) }

        it 'does not raise an error' do
          expect { execute_service }.not_to raise_error
        end
      end

      context 'when the project is missing' do
        let_it_be(:project, freeze: false) { create(:project).tap(&:delete) }

        it 'does not raise an exception' do
          expect { execute_service }.not_to raise_error
        end

        it "returns a service response error" do
          response = execute_service

          expect(response).to be_error
          expect(response.http_status).to eq :bad_request
          expect(response.message).to eq "Failed to schedule pipeline."
        end

        it 'does not run RunPipelineScheduleWorker' do
          expect(RunPipelineScheduleWorker)
            .not_to receive(:perform_async).with(schedule.id, schedule.owner.id)

          execute_service
        end
      end

      context 'when the project is archived' do
        around do |example|
          project.update!(archived: true)
          example.run
        ensure
          project.update!(archived: false)
        end

        it 'does not raise an exception' do
          expect { execute_service }.not_to raise_error
        end

        it "returns a service response error" do
          response = execute_service

          expect(response).to be_error
          expect(response.http_status).to eq :bad_request
          expect(response.message).to eq "Failed to schedule pipeline."
        end

        it 'does not run RunPipelineScheduleWorker' do
          expect(RunPipelineScheduleWorker)
            .not_to receive(:perform_async).with(schedule.id, schedule.owner.id)

          execute_service
        end
      end
    end

    context 'when user can not play the schedule' do
      before do
        allow(service).to receive(:can?).with(user, :play_pipeline_schedule, schedule).and_return(false)
      end

      it 'raises an AccessDeniedError' do
        expect { execute_service }.to raise_error Gitlab::Access::AccessDeniedError
      end
    end

    context 'with rate limiting', :freeze_time do
      let(:throttle_message) { _('You cannot play this scheduled pipeline at the moment. Please wait a minute.') }

      before do
        allow(service).to receive(:can?).with(user, :play_pipeline_schedule, anything).and_return(true)
      end

      it 'plays the schedule while under the limit' do
        expect(execute_service).to be_success
      end

      it 'throttles the second play of the same schedule in a minute', :aggregate_failures do
        expect(service.execute(schedule)).to be_success

        expect(RunPipelineScheduleWorker).not_to receive(:perform_async)

        response = service.execute(schedule)

        expect(response).to be_error
        expect(response.reason).to eq(:rate_limited)
        expect(response.message).to eq(throttle_message)
      end

      it 'does not throttle a play of another schedule' do
        other_schedule = create(:ci_pipeline_schedule, project: project, owner: user)
        service.execute(schedule)

        expect(service.execute(other_schedule)).to be_success
      end

      it 'does not throttle a play by another user' do
        other_user = create(:user)
        other_service = described_class.new(project, other_user)
        allow(other_service).to receive(:can?).with(other_user, :play_pipeline_schedule, schedule).and_return(true)
        service.execute(schedule)

        expect(other_service.execute(schedule)).to be_success
      end

      it 'counts an attempt that is denied access', :aggregate_failures do
        allow(service).to receive(:can?).with(user, :play_pipeline_schedule, schedule).and_return(false, true)

        expect { service.execute(schedule) }.to raise_error(Gitlab::Access::AccessDeniedError)

        response = service.execute(schedule)

        expect(response).to be_error
        expect(response.reason).to eq(:rate_limited)
      end

      it 'logs the throttled play' do
        allow(Gitlab::AppJsonLogger).to receive(:info)

        2.times { service.execute(schedule) }

        expect(Gitlab::AppJsonLogger).to have_received(:info).with(
          a_hash_including(
            Labkit::Fields::CLASS_NAME => described_class.to_s,
            message: 'Pipeline schedule play rate limit exceeded',
            rate_limit: 'play_pipeline_schedule',
            Labkit::Fields::GL_PROJECT_ID => project.id,
            Labkit::Fields::GL_USER_ID => user.id,
            pipeline_schedule_id: schedule.id
          )
        ).once
      end

      context 'without a user' do
        let(:service) { described_class.new(project, nil) }

        before do
          allow(service).to receive(:can?).with(nil, :play_pipeline_schedule, schedule).and_return(true)
          allow(RunPipelineScheduleWorker).to receive(:perform_async).and_return('job-123')
        end

        it 'does not throttle' do
          2.times { expect(service.execute(schedule)).to be_success }
        end
      end
    end
  end
end
