# frozen_string_literal: true

require 'spec_helper'

# A granular PAT without a matching scope reaches a public project only through the public
# access rule of Authz::BoundaryPolicy. Such a request is served as anonymous, so a member's
# token cannot read what the member could read with a token that holds the permission.
RSpec.describe 'Granular token public access', feature_category: :permissions do
  include GraphqlHelpers

  let_it_be(:member) { create(:user) }
  let_it_be_with_reload(:project) { create(:project, :public, :repository, maintainers: member) }
  let_it_be(:open_issue) { create(:issue, project: project) }
  let_it_be(:confidential_issue) { create(:issue, :confidential, project: project) }
  let_it_be(:pipeline) { create(:ci_pipeline, project: project) }
  let_it_be(:schedule) { create(:ci_pipeline_schedule, project: project, owner: member) }
  let_it_be(:schedule_variable) do
    create(:ci_pipeline_schedule_variable, pipeline_schedule: schedule, key: 'DEPLOY_KEY', value: 'schedule-secret')
  end

  let_it_be(:scopeless_token) { create(:granular_pat, user: member) }

  def granted_token(*permissions)
    assignables = permissions.map { |p| ::Authz::PermissionGroups::Assignable.preferred_for_permission(p).name }

    create(:granular_pat, user: member, boundary: ::Authz::Boundary.for(project), permissions: assignables.uniq)
  end

  describe 'REST' do
    describe 'GET /projects/:id/issues' do
      it 'lists only the issues an anonymous user sees' do
        get api("/projects/#{project.id}/issues", personal_access_token: scopeless_token)

        expect(response).to have_gitlab_http_status(:ok)
        expect(json_response.pluck('id')).to contain_exactly(open_issue.id)
      end

      it 'lists the confidential issue to a token that holds the permission' do
        get api("/projects/#{project.id}/issues", personal_access_token: granted_token(:read_issue))

        expect(json_response.pluck('id')).to contain_exactly(open_issue.id, confidential_issue.id)
      end
    end

    describe 'GET /projects/:id/issues/:issue_iid' do
      it 'does not find the confidential issue' do
        get api("/projects/#{project.id}/issues/#{confidential_issue.iid}", personal_access_token: scopeless_token)

        expect(response).to have_gitlab_http_status(:not_found)
      end
    end

    describe 'GET /projects/:id/pipelines/:pipeline_id' do
      before do
        project.update!(public_builds: false)
      end

      it 'denies a pipeline that public pipelines setting hides' do
        get api("/projects/#{project.id}/pipelines/#{pipeline.id}", personal_access_token: scopeless_token)

        expect(response).to have_gitlab_http_status(:forbidden)
      end

      it 'returns the pipeline to a token that holds the permission' do
        get api("/projects/#{project.id}/pipelines/#{pipeline.id}",
          personal_access_token: granted_token(:read_pipeline))

        expect(response).to have_gitlab_http_status(:ok)
      end
    end

    describe 'GET /projects/:id/pipeline_schedules/:pipeline_schedule_id' do
      let(:path) { "/projects/#{project.id}/pipeline_schedules/#{schedule.id}" }

      it 'denies an endpoint that requires authentication' do
        get api(path, personal_access_token: scopeless_token)

        expect(response).to have_gitlab_http_status(:forbidden)
        expect(json_response['error']).to eq('insufficient_granular_scope')
      end

      it 'returns the variables to a token that holds the permission' do
        get api(path, personal_access_token: granted_token(:read_pipeline_schedule))

        expect(response).to have_gitlab_http_status(:ok)
        expect(json_response['variables']).to contain_exactly(a_hash_including('value' => 'schedule-secret'))
      end
    end

    it 'logs the token user for a request served as anonymous' do
      get api("/projects/#{project.id}/issues", personal_access_token: scopeless_token)

      expect(request.env[API::Helpers::API_USER_ENV]).to include(user_id: member.id)
    end
  end

  describe 'GraphQL' do
    let(:query) do
      graphql_query_for(:project, { full_path: project.full_path },
        query_graphql_field(:issue, { iid: confidential_issue.iid.to_s }, 'title')
      )
    end

    it 'does not return the confidential issue' do
      post_graphql(query, token: { personal_access_token: scopeless_token })

      expect(graphql_errors).to be_nil
      expect(graphql_data_at(:project)).to be_present
      expect(graphql_data_at(:project, :issue)).to be_nil
    end

    it 'returns the confidential issue to a token that holds the permissions' do
      post_graphql(query, token: { personal_access_token: granted_token(:read_project, :read_issue) })

      expect(graphql_data_at(:project, :issue, :title)).to eq(confidential_issue.title)
    end

    describe 'a mutation that loads an object only the public access rule admits' do
      let_it_be(:merge_request) { create(:merge_request, source_project: project) }
      let_it_be(:milestone) { create(:milestone, project: project) }

      let(:mutation) do
        graphql_mutation(:merge_request_set_milestone, {
          project_path: project.full_path,
          iid: merge_request.iid.to_s,
          milestone_id: milestone.to_global_id.to_s
        }, 'errors')
      end

      it 'runs as the token user when the token holds the permission of the mutation' do
        post_graphql_mutation(mutation, token: { personal_access_token: granted_token(:update_merge_request) })

        expect(graphql_errors).to be_nil
        expect(merge_request.reload.milestone).to eq(milestone)
      end
    end

    describe 'a count batched with an object the token holds the permission for' do
      let_it_be(:members_only_mrs) do
        create(:project, :public, :repository, :merge_requests_private, maintainers: member)
      end

      let_it_be(:public_issue) { create(:issue, project: members_only_mrs) }

      let(:query) do
        <<~GRAPHQL
          {
            granted: project(fullPath: "#{project.full_path}") { issues { nodes { mergeRequestsCount } } }
            public: project(fullPath: "#{members_only_mrs.full_path}") { issues { nodes { mergeRequestsCount } } }
          }
        GRAPHQL
      end

      before_all do
        create(:merge_request_issue, issue: public_issue,
          merge_request: create(:merge_request, source_project: members_only_mrs))
      end

      it 'counts as anonymous for the object only the public access rule admits' do
        post_graphql(query, token: { personal_access_token: granted_token(:read_project, :read_issue) })

        expect(graphql_errors).to be_nil
        expect(graphql_data_at(:granted, :issues, :nodes)).to be_present
        expect(graphql_data_at(:public, :issues, :nodes)).to contain_exactly({ 'mergeRequestsCount' => 0 })
      end
    end
  end
end
