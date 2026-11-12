# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'PipelineScheduleDelete', feature_category: :continuous_integration do
  include GraphqlHelpers

  let_it_be(:current_user) { create(:user) }
  let_it_be(:project) { create(:project) }
  let_it_be(:pipeline_schedule) { create(:ci_pipeline_schedule, project: project, owner: current_user) }

  let(:mutation) do
    graphql_mutation(
      :pipeline_schedule_delete,
      { id: pipeline_schedule_id },
      <<-QL
        errors
      QL
    )
  end

  let(:pipeline_schedule_id) { pipeline_schedule.to_global_id.to_s }
  let(:mutation_response) { graphql_mutation_response(:pipeline_schedule_delete) }

  context 'when unauthorized' do
    it_behaves_like 'a mutation on an unauthorized resource'
  end

  context 'when authorized' do
    before_all do
      project.add_maintainer(current_user)
    end

    it_behaves_like 'authorizing granular token permissions for GraphQL', :delete_pipeline_schedule do
      let(:user) { current_user }
      let(:boundary_object) { project }
      let(:request) { post_graphql_mutation(mutation, token: { personal_access_token: pat }) }
    end

    context 'when success' do
      it 'returns no errors' do
        post_graphql_mutation(mutation, current_user: current_user)

        expect(response).to have_gitlab_http_status(:success)
        expect(mutation_response['errors']).to eq([])
      end
    end

    context 'when failure' do
      context 'when destroy fails' do
        before do
          allow_next_found_instance_of(Ci::PipelineSchedule) do |pipeline_schedule|
            allow(pipeline_schedule).to receive(:destroy).and_return(false)
          end
        end

        it 'returns a failed to remove error' do
          post_graphql_mutation(mutation, current_user: current_user)

          expect(response).to have_gitlab_http_status(:success)

          expect(mutation_response['errors']).to match_array(['Failed to remove the pipeline schedule'])
        end
      end

      context 'when pipeline schedule not found' do
        let(:pipeline_schedule_id) { 'gid://gitlab/Ci::PipelineSchedule/0' }

        it 'returns an internal server error for the missing schedule' do
          post_graphql_mutation(mutation, current_user: current_user)

          expect(graphql_errors).not_to be_empty
          expect(graphql_errors[0]['message'])
            .to eq("Internal server error: Couldn't find Ci::PipelineSchedule with 'id'=\"0\"")
        end
      end
    end
  end

  context 'when the pipeline schedule management rate limit is exceeded', :clean_gitlab_redis_rate_limiting,
    :freeze_time do
    let(:other_pipeline_schedule) { create(:ci_pipeline_schedule, project: project, owner: current_user) }

    let(:other_mutation) do
      graphql_mutation(:pipeline_schedule_delete, { id: other_pipeline_schedule.to_global_id.to_s }, 'errors')
    end

    before_all do
      project.add_maintainer(current_user)
    end

    before do
      stub_application_setting(pipeline_schedule_management_limit_per_user: 1)
    end

    it 'surfaces the throttle in the mutation errors', :aggregate_failures do
      post_graphql_mutation(other_mutation, current_user: current_user)
      expect(graphql_mutation_response(:pipeline_schedule_delete)['errors']).to be_empty

      post_graphql_mutation(mutation, current_user: current_user)

      expect(response).to have_gitlab_http_status(:success)
      expect(graphql_mutation_response(:pipeline_schedule_delete)['errors'])
        .to contain_exactly(_('This endpoint has been requested too many times. Try again later.'))
      expect(Ci::PipelineSchedule.exists?(pipeline_schedule.id)).to be(true)
    end
  end
end
