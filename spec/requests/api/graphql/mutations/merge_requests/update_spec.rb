# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'Update of an existing merge request', feature_category: :code_review_workflow do
  include GraphqlHelpers

  let_it_be(:current_user) { create(:user) }
  let_it_be(:group) { create(:group) }
  let_it_be(:project) { create(:project, :repository, :public, group: group) }
  let_it_be_with_reload(:merge_request) { create(:merge_request, :simple, source_project: project) }

  let(:input) { { 'iid' => merge_request.iid.to_s, project_path: project.full_path } }
  let(:extra_params) { {} }
  let(:input_params) { input.merge(extra_params) }
  let(:mutation_response) { graphql_mutation_response(:merge_request_update) }
  let(:mutation) do
    # exclude codequalityReportsComparer because it's behind a feature flag
    graphql_mutation(:merge_request_update, input_params, nil, %w[productAnalyticsState codequalityReportsComparer])
  end

  context 'when the user is not allowed to update the merge request' do
    it_behaves_like 'a mutation that returns a top-level access error'
  end

  context 'when the user has permissions to update the merge request' do
    before_all do
      group.add_developer(current_user)
    end

    it_behaves_like 'authorizing granular token permissions for GraphQL', :update_merge_request do
      let(:user) { current_user }
      let(:boundary_object) { project }
      let(:mutation) { graphql_mutation(:merge_request_update, input_params, 'errors') }
      let(:request) { post_graphql_mutation(mutation, token: { personal_access_token: pat }) }
    end

    it_behaves_like 'updating time estimate' do
      let(:resource) { merge_request }
      let(:mutation_name) { 'mergeRequestUpdate' }
    end

    context 'when clearing merge schedule fields', :freeze_time do
      let(:scheduled_start) { 1.day.from_now }
      let(:scheduled_end) { scheduled_start + 1.hour }
      let(:mutation) do
        graphql_mutation(:merge_request_update, input_params, 'mergeRequest { mergeAfter mergeBefore } errors')
      end

      before do
        merge_request.create_merge_schedule!(merge_after: scheduled_start, merge_before: scheduled_end)
      end

      context 'when only the end time is null' do
        let(:extra_params) { { merge_before: nil } }

        it 'clears the end time and preserves the start time', :aggregate_failures do
          post_graphql_mutation(mutation, current_user: current_user)

          expect(graphql_errors).to be_nil
          expect(mutation_response['errors']).to be_empty
          expect(merge_request.reload.merge_schedule).to have_attributes(
            merge_after: scheduled_start, merge_before: nil)
          expect(mutation_response['mergeRequest']['mergeBefore']).to be_nil
        end
      end

      context 'when moving the start past the old end time and clearing the end time' do
        let(:extra_params) { { merge_after: scheduled_end + 1.hour, merge_before: nil } }

        it 'saves the later start time without an end time', :aggregate_failures do
          post_graphql_mutation(mutation, current_user: current_user)

          expect(graphql_errors).to be_nil
          expect(mutation_response['errors']).to be_empty
          expect(merge_request.reload.merge_schedule).to have_attributes(
            merge_after: scheduled_end + 1.hour, merge_before: nil)
        end
      end

      context 'when both times are null' do
        let(:extra_params) { { merge_after: nil, merge_before: nil } }

        it 'removes the schedule', :aggregate_failures do
          post_graphql_mutation(mutation, current_user: current_user)

          expect(graphql_errors).to be_nil
          expect(mutation_response['errors']).to be_empty
          expect(merge_request.reload.merge_schedule).to be_nil
        end
      end

      context 'when schedule arguments are omitted' do
        let(:extra_params) { { title: 'Updated title' } }

        it 'preserves the schedule', :aggregate_failures do
          post_graphql_mutation(mutation, current_user: current_user)

          expect(graphql_errors).to be_nil
          expect(mutation_response['errors']).to be_empty
          expect(merge_request.reload).to have_attributes(title: 'Updated title')
          expect(merge_request.merge_schedule).to have_attributes(
            merge_after: scheduled_start, merge_before: scheduled_end)
        end
      end

      context 'when the start time is null but the end time is retained' do
        let(:extra_params) { { merge_after: nil } }

        it 'returns a validation error and preserves the stored schedule', :aggregate_failures do
          post_graphql_mutation(mutation, current_user: current_user)

          expect(graphql_errors).to be_nil
          expect(mutation_response['errors']).to include("Merge schedule merge after can't be blank")
          expect(merge_request.reload.merge_schedule).to have_attributes(
            merge_after: scheduled_start, merge_before: scheduled_end)
        end
      end
    end

    context 'when updating the description' do
      context 'when the description uses the work item closing pattern', :sidekiq_inline do
        let(:work_item) { create(:work_item, :task, project: project) }
        let(:extra_params) { { description: "Closes #{Gitlab::UrlBuilder.build(work_item)}" } }

        it 'creates a merge request closing issue record' do
          expect do
            post_graphql_mutation(mutation, current_user: current_user)
          end.to change { MergeRequestIssue.count }.by(1)
        end
      end
    end

    context 'when reopening a merge request whose source branch no longer exists' do
      let_it_be_with_reload(:merge_request) do
        create(:merge_request, :closed, source_project: project, source_branch: 'this-source-branch-does-not-exist')
      end

      let(:extra_params) { { state: 'OPEN' } }
      let(:mutation) do
        graphql_mutation(:merge_request_update, input_params, <<~FIELDS)
          mergeRequest { state }
          errors
        FIELDS
      end

      it 'does not reopen the merge request and returns an error' do
        post_graphql_mutation(mutation, current_user: current_user)

        expect(mutation_response['mergeRequest']['state']).to eq('closed')
        expect(mutation_response['errors'])
          .to include('Cannot reopen this merge request because the source or target branch no longer exists.')
      end
    end

    context 'when required arguments are missing' do
      let(:input_params) { {} }

      it_behaves_like 'a mutation that returns top-level errors' do
        let(:match_errors) do
          include(end_with(
            'invalid value for projectPath (Expected value to not be null), iid (Expected value to not be null)'
          ))
        end
      end
    end
  end
end
