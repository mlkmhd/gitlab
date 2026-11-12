# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'search_rate_limit', :api, :clean_gitlab_redis_rate_limiting,
  feature_category: :mcp_server do
  include GraphqlHelpers

  let_it_be(:user) { create(:user) }
  let_it_be(:project) { create(:project, :public, maintainers: [user]) }
  let_it_be(:access_token) { create(:oauth_access_token, user: user, scopes: [:mcp]) }

  let(:rate_limit_error) do
    {
      'type' => 'rate_limited',
      'limit' => 'search_rate_limit',
      'retry_after_seconds' => 60,
      'message' => 'This endpoint has been requested with the search argument too many times. Try again later.'
    }
  end

  before do
    stub_application_setting(
      instance_level_ai_beta_features_enabled: true,
      mcp_server_enabled: true,
      search_rate_limit: 1
    )
  end

  def call_tool(name, arguments)
    post api('/mcp', user, oauth_access_token: access_token), params: {
      jsonrpc: '2.0', method: 'tools/call', id: '1',
      params: { name: name, arguments: arguments }
    }, as: :json

    expect(response).to have_gitlab_http_status(:ok)
    json_response.fetch('result')
  end

  def search_arguments
    { project_id: project.id.to_s, search: 'test', first: 1 }
  end

  shared_examples 'a search-throttled tool' do |tool_name|
    it 'throttles a second call with a search argument' do
      first = call_tool(tool_name, search_arguments)
      expect(first['isError']).to be(false)

      second = call_tool(tool_name, search_arguments)
      expect(second['isError']).to be(true)
      expect(second['structuredContent']).to eq('error' => rate_limit_error)
    end

    it 'does not throttle repeated calls without a search argument' do
      2.times do
        result = call_tool(tool_name, search_arguments.except(:search))
        expect(result['isError']).to be(false)
      end
    end
  end

  it_behaves_like 'a search-throttled tool', 'list_merge_requests'
  it_behaves_like 'a search-throttled tool', 'list_work_items'

  it 'shares one per-user budget across tools' do
    first = call_tool('list_merge_requests', search_arguments)
    expect(first['isError']).to be(false)

    second = call_tool('list_work_items', search_arguments)
    expect(second['isError']).to be(true)
    expect(second['structuredContent']).to eq('error' => rate_limit_error)
  end

  context 'with /api/graphql' do
    let(:graphql_query) do
      graphql_query_for(
        :project, { full_path: project.full_path },
        query_graphql_field(:merge_requests, { search: 'test' }, 'nodes { iid }')
      )
    end

    it 'throttles a tool call once /api/graphql used the budget' do
      post_graphql(graphql_query, current_user: user)
      expect(graphql_errors).to be_nil

      result = call_tool('list_merge_requests', search_arguments)
      expect(result['isError']).to be(true)
      expect(result['structuredContent']).to eq('error' => rate_limit_error)
    end

    it 'throttles /api/graphql once a tool call used the budget' do
      expect(call_tool('list_merge_requests', search_arguments)['isError']).to be(false)

      post_graphql(graphql_query, current_user: user)
      expect(graphql_errors.to_s).to match(/too many times/)
      expect(graphql_errors.first['extensions']).to eq(
        'error_type' => 'rate_limited', 'limit' => 'search_rate_limit', 'retry_after_seconds' => 60
      )
    end
  end
end
