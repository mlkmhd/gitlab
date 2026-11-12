# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'getting merge request information nested in a project', feature_category: :code_review_workflow do
  include GraphqlHelpers

  let_it_be(:current_user) { create(:user) }
  let_it_be(:project) { create(:project, :public) }

  let(:merge_request) { create(:merge_request, source_project: project) }
  let(:merge_request_graphql_data) { graphql_data_at(:project, :merge_request) }
  let(:mr_fields) { "suggestedReviewers { #{all_graphql_fields_for('SuggestedReviewersType')} }" }
  let(:suggested_reviewers) do
    {
      'version' => '0.0.0',
      'top_n' => 1,
      'reviewers' => %w[bmarley swayne]
    }
  end

  let(:accepted_reviewers) do
    {
      'reviewers' => %w[bmarley]
    }
  end

  let(:api_result) do
    {
      'accepted' => %w[bmarley],
      'suggested' => %w[bmarley swayne]
    }
  end

  let(:query) do
    graphql_query_for(
      :project,
      { full_path: project.full_path },
      query_graphql_field(:merge_request, { iid: merge_request.iid.to_s }, mr_fields)
    )
  end

  describe 'suggestedReviewers' do
    before do
      merge_request.build_predictions
      merge_request.predictions.update!(
        suggested_reviewers: suggested_reviewers,
        accepted_reviewers: accepted_reviewers
      )
      allow_any_instance_of(Project) # rubocop:disable RSpec/AnyInstanceOf
        .to receive(:can_suggest_reviewers?).and_return(available)
    end

    shared_examples 'feature available' do
      it 'returns the right suggested reviewers' do
        post_graphql(query, current_user: current_user)

        expected_data = {
          'suggestedReviewers' => a_hash_including(api_result)
        }

        expect(merge_request_graphql_data).to include(expected_data)
      end
    end

    shared_examples 'feature unavailable' do
      it 'returns nil' do
        post_graphql(query, current_user: current_user)

        expected_data = {
          'suggestedReviewers' => nil
        }

        expect(merge_request_graphql_data).to include(expected_data)
      end
    end

    context 'when suggested reviewers is available for the project' do
      let(:available) { true }

      include_examples 'feature available'
    end

    context 'when suggested reviewers is not available for the project' do
      let(:available) { false }

      include_examples 'feature unavailable'
    end
  end

  describe 'duoWorkflows' do
    let_it_be(:group) { create(:group) }
    let_it_be(:project) { create(:project, :public, group: group) }
    let_it_be(:current_user) { create(:user, developer_of: group) }
    let_it_be(:merge_request) { create(:merge_request, source_project: project) }
    let_it_be(:duo_workflow) do
      create(:duo_workflows_workflow, project: project, user: current_user, merge_request: merge_request)
    end

    let_it_be(:chat_workflow) do
      create(:duo_workflows_workflow, :agentic_chat, project: project, user: current_user, merge_request: merge_request)
    end

    let(:mr_fields) do
      <<~GRAPHQL
        duoWorkflows {
          nodes {
            id
          }
        }
      GRAPHQL
    end

    context 'when ai_workflows feature is licensed' do
      before do
        stub_licensed_features(ai_workflows: true)
        allow(::Gitlab::Llm::StageCheck).to receive(:available?).and_call_original
        allow(::Gitlab::Llm::StageCheck).to receive(:available?).with(project, :duo_workflow).and_return(true)
        allow_any_instance_of(User).to receive(:allowed_to_use).and_return( # rubocop:disable RSpec/AnyInstanceOf -- not the next instance
          Ai::UserAuthorizable::Response.new(allowed?: true, namespace_ids: [group.id])
        )

        post_graphql(query, current_user: current_user)
      end

      it 'returns duo workflows' do
        expect(merge_request_graphql_data).to include(
          'duoWorkflows' => {
            'nodes' => [
              { 'id' => duo_workflow.to_gid.to_s }
            ]
          }
        )
      end

      it 'does not return chat sessions' do
        ids = merge_request_graphql_data.dig('duoWorkflows', 'nodes').pluck('id')

        expect(ids).to include(duo_workflow.to_gid.to_s)
        expect(ids).not_to include(chat_workflow.to_gid.to_s)
      end

      context 'when the sessions select per-session fields' do
        let(:mr_fields) do
          <<~GRAPHQL
            duoWorkflows {
              nodes {
                id
                agentName
                userPermissions {
                  restartDuoWorkflow
                }
                user {
                  id
                  username
                }
                project {
                  id
                  fullPath
                }
              }
            }
          GRAPHQL
        end

        # skip_cached: false, because a per-session project load repeats identical SQL and would
        # otherwise be hidden by the query cache.
        it 'avoids N+1 queries as more sessions are linked', :request_store, :use_sql_query_cache do
          control = ActiveRecord::QueryRecorder.new(skip_cached: false) do
            post_graphql(query, current_user: current_user)
          end

          create_list(:duo_workflows_workflow, 2, project: project, merge_request: merge_request)
          create_list(:duo_workflows_workflow, 2, :failed, project: project, user: current_user,
            merge_request: merge_request)

          expect do
            post_graphql(query, current_user: current_user)
          end.not_to exceed_all_query_limit(control)
        end
      end
    end

    context 'when ai_workflows feature is unlicensed' do
      before do
        stub_licensed_features(ai_workflows: false)

        post_graphql(query, current_user: current_user)
      end

      it 'returns nil' do
        expect(merge_request_graphql_data['duoWorkflows']).to be_nil
      end
    end
  end

  describe 'child types with a granular token' do
    let_it_be(:project) { create(:project, :private) }
    let_it_be(:user) { create(:user, developer_of: project) }

    let(:boundary_object) { project }
    let(:request) { post_graphql(query, token: { personal_access_token: pat }) }

    context 'when loading the suggested reviewers' do
      let(:mr_fields) { 'suggestedReviewers { suggested }' }

      before do
        merge_request.build_predictions
        merge_request.predictions.update!(suggested_reviewers: suggested_reviewers)

        allow_next_found_instance_of(Project) do |instance|
          allow(instance).to receive(:can_suggest_reviewers?).and_return(true)
        end
      end

      it_behaves_like 'authorizing granular token permissions for GraphQL with a skipped child type',
        [:read_project, :read_merge_request] do
        let(:skipped_data_path) { %i[project merge_request suggested_reviewers] }
      end
    end

    context 'when loading the blocking merge requests' do
      let(:mr_fields) { 'blockingMergeRequests { totalCount hiddenCount }' }
      let(:pat) do
        create(:granular_pat, user: user, boundary: ::Authz::Boundary.for(project),
          permissions: %w[read_project read_merge_request])
      end

      it 'returns them to a token with read_merge_request_dependency', :aggregate_failures do
        request

        expect(graphql_errors).to be_nil
        expect(graphql_data_at(:project, :merge_request, :blocking_merge_requests))
          .to eq({ 'totalCount' => 0, 'hiddenCount' => 0 })
      end

      context 'when the token is not granted read_merge_request_dependency' do
        # Merge Request: Read carries read_merge_request_dependency, so the token is stubbed without it.
        before do
          allow_next_found_instance_of(PersonalAccessToken) do |token|
            allow(token).to receive(:permitted_for_boundary?).and_call_original
            allow(token).to receive(:permitted_for_boundary?)
              .with(anything, :read_merge_request_dependency).and_return(false)
          end
        end

        it 'returns the merge request without them', :aggregate_failures do
          request

          expect(graphql_errors).to be_nil
          expect(graphql_data_at(:project, :merge_request)).to be_present
          expect(graphql_data_at(:project, :merge_request, :blocking_merge_requests)).to be_nil
        end
      end

      context 'when a blocker is in a project the token does not cover' do
        let_it_be(:other_project) { create(:project, :private, developers: user) }

        let(:mr_fields) { 'blockingMergeRequests { visibleMergeRequests { id } }' }
        let(:blocker) { create(:merge_request, :unique_branches, source_project: project) }

        before do
          create(:merge_request_block, blocking_merge_request: blocker, blocked_merge_request: merge_request)
          create(:merge_request_block, blocked_merge_request: merge_request,
            blocking_merge_request: create(:merge_request, source_project: other_project))
        end

        it 'returns only the blockers in the project the token covers', :aggregate_failures do
          request

          expect(graphql_errors).to be_nil
          expect(graphql_data_at(:project, :merge_request, :blocking_merge_requests, :visible_merge_requests))
            .to contain_exactly({ 'id' => blocker.to_global_id.to_s })
        end
      end
    end

    context 'when loading the diff versions' do
      let(:mr_fields) { 'mergeRequestDiffs { nodes { createdAt } }' }

      it_behaves_like 'authorizing granular token permissions for GraphQL with a skipped child type',
        [:read_project, :read_merge_request] do
        let(:skipped_data_path) { [:project, :merge_request, :merge_request_diffs, :nodes, 0, :created_at] }
      end
    end
  end
end
