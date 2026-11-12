# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'mcp scope route restriction', feature_category: :mcp_server do
  let_it_be(:user) { create(:user) }
  let_it_be(:project) { create(:project, :repository, creator: user) }
  let_it_be(:pipeline) { create(:ci_pipeline, project: project) }
  let_it_be(:merge_request) { create(:merge_request, source_project: project, target_project: project) }
  let_it_be(:mcp_token) { create(:personal_access_token, user: user, scopes: [:mcp]) }

  before_all do
    project.add_maintainer(user)
  end

  describe 'GET /projects/:id/pipelines' do
    it 'is allowed, since this route is a registered mcp tool' do
      get api("/projects/#{project.id}/pipelines", personal_access_token: mcp_token)

      expect(response).to have_gitlab_http_status(:ok)
    end
  end

  # Pipeline variables often hold credentials, and this route is not an mcp tool, so an
  # mcp-scoped token must not reach it even though it shares a verb with the tool routes.
  describe 'GET /projects/:id/pipelines/:pipeline_id/variables' do
    it 'is rejected, since this route is not a registered mcp tool' do
      get api("/projects/#{project.id}/pipelines/#{pipeline.id}/variables", personal_access_token: mcp_token)

      expect(response).to have_gitlab_http_status(:forbidden)
      expect(json_response['error']).to eq('insufficient_scope')
    end
  end

  describe 'PUT /projects/:id/merge_requests/:merge_request_iid' do
    it 'is allowed, since this route is a registered mcp tool' do
      put api("/projects/#{project.id}/merge_requests/#{merge_request.iid}", personal_access_token: mcp_token),
        params: { title: 'Updated title' }

      expect(response).to have_gitlab_http_status(:ok)
    end
  end

  # Merging bypasses review requirements, and this route is not an mcp tool, so an
  # mcp-scoped token must not reach it even though it shares a verb with the tool route above.
  describe 'PUT /projects/:id/merge_requests/:merge_request_iid/merge' do
    it 'is rejected, since this route is not a registered mcp tool' do
      put api("/projects/#{project.id}/merge_requests/#{merge_request.iid}/merge", personal_access_token: mcp_token)

      expect(response).to have_gitlab_http_status(:forbidden)
      expect(json_response['error']).to eq('insufficient_scope')
    end
  end

  describe 'mcp_request_origin log field' do
    before do
      allow(API::API::LOGGER).to receive(:info).and_call_original
    end

    it 'is external when an mcp-scoped token calls a tool route directly' do
      get api("/projects/#{project.id}/pipelines", personal_access_token: mcp_token)

      expect(response).to have_gitlab_http_status(:ok)
      expect(API::API::LOGGER).to have_received(:info).with(hash_including(mcp_request_origin: 'external'))
    end

    it 'is mcp_server when the MCP server dispatches the tool route' do
      stub_application_setting(instance_level_ai_beta_features_enabled: true)

      post api('/mcp', personal_access_token: mcp_token), params: {
        jsonrpc: '2.0',
        method: 'tools/call',
        params: { name: 'list_pipelines', arguments: { id: project.full_path } },
        id: '1'
      }

      expect(response).to have_gitlab_http_status(:ok)
      expect(json_response.dig('result', 'isError')).to be_falsey
      expect(API::API::LOGGER).to have_received(:info)
        .with(hash_including(mcp_request_origin: 'mcp_server')).at_least(:once)
    end

    it 'is not logged when another scope of the token authorizes the route' do
      api_token = create(:personal_access_token, user: user, scopes: [:mcp, :read_api])

      get api("/projects/#{project.id}/pipelines", personal_access_token: api_token)

      expect(response).to have_gitlab_http_status(:ok)
      expect(API::API::LOGGER).not_to have_received(:info).with(hash_including(:mcp_request_origin))
    end

    it 'is not logged when sudo authorizes the route', :enable_admin_mode do
      admin = create(:admin)
      sudo_token = create(:personal_access_token, user: admin, scopes: [:mcp, :sudo])

      get api("/projects/#{project.id}/pipelines", personal_access_token: sudo_token), params: { sudo: user.id }

      expect(response).to have_gitlab_http_status(:ok)
      expect(API::API::LOGGER).not_to have_received(:info).with(hash_including(:mcp_request_origin))
    end
  end
end
