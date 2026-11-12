# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Ci::PipelineSchedules::TakeOwnershipService, feature_category: :continuous_integration do
  let_it_be(:user) { create(:user) }
  let_it_be(:owner) { create(:user) }
  let_it_be(:reporter) { create(:user) }
  let_it_be(:project) do
    create(:project, :public, maintainers: [user, owner], reporters: reporter)
  end

  let_it_be(:pipeline_schedule, freeze: false) { create(:ci_pipeline_schedule, project: project, owner: owner) }

  describe '#execute' do
    context 'when user does not have permission' do
      subject(:service) { described_class.new(pipeline_schedule, reporter) }

      it 'returns ServiceResponse.error' do
        result = service.execute

        expect(result).to be_a(ServiceResponse)
        expect(result.error?).to be(true)
        expect(result.message).to eq(_('Failed to change the owner'))
      end
    end

    context 'when user has permission' do
      subject(:service) { described_class.new(pipeline_schedule, user) }

      it 'returns ServiceResponse.success' do
        result = service.execute

        expect(result).to be_a(ServiceResponse)
        expect(result.success?).to be(true)
        expect(result.payload).to eq(pipeline_schedule)
      end

      context 'when schedule update fails' do
        subject(:service) { described_class.new(pipeline_schedule, owner) }

        before do
          errors = ActiveModel::Errors.new(pipeline_schedule)
          errors.add(:base, 'An error occurred')
          allow(pipeline_schedule).to receive_messages(update: false, errors: errors)
        end

        it 'returns ServiceResponse.error' do
          result = service.execute

          expect(result).to be_a(ServiceResponse)
          expect(result.error?).to be(true)
          expect(result.message).to eq(['An error occurred'])
        end
      end
    end

    context 'with rate limiting', :clean_gitlab_redis_rate_limiting, :freeze_time do
      let(:unauthorized_user) { reporter }

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
          execute_service
        end

        it 'leaves the owner unchanged' do
          described_class.new(schedule, user).execute

          expect(schedule.reload.owner).to eq(owner)
        end
      end
    end
  end
end
