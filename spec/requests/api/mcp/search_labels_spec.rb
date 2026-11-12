# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'search_labels', :api, feature_category: :mcp_server do
  let_it_be(:user) { create(:user) }
  let_it_be(:project) { create(:project, :public, maintainers: [user]) }
  let_it_be(:label) { create(:label, project: project, title: 'backend-bug') }
  let_it_be(:access_token) { create(:oauth_access_token, user: user, scopes: [:mcp]) }

  before do
    stub_application_setting(instance_level_ai_beta_features_enabled: true, mcp_server_enabled: true)
  end

  def call_search(search)
    post api('/mcp', user, oauth_access_token: access_token), params: {
      jsonrpc: '2.0', method: 'tools/call', id: '1',
      params: { name: 'search_labels', arguments: { full_path: project.full_path, is_project: true, search: search } }
    }, as: :json

    expect(response).to have_gitlab_http_status(:ok)
    json_response.fetch('result')
  end

  it 'accepts existing scalar search calls without version selection' do
    result = call_search('bug')

    expect(result['isError']).to be(false)
    expect(result.dig('structuredContent', 'items')).to include(a_hash_including('id' => label.to_global_id.to_s))
  end

  it 'accepts project_id instead of full_path and is_project' do
    post api('/mcp', user, oauth_access_token: access_token), params: {
      jsonrpc: '2.0', method: 'tools/call', id: '1',
      params: { name: 'search_labels', arguments: { project_id: project.full_path, search: 'bug' } }
    }, as: :json

    expect(response).to have_gitlab_http_status(:ok)
    result = json_response.fetch('result')

    expect(result['isError']).to be(false)
    expect(result.dig('structuredContent', 'items')).to include(a_hash_including('id' => label.to_global_id.to_s))
  end

  it 'accepts batch search calls without version selection' do
    result = call_search(%w[backend bug])

    expect(result['isError']).to be(false)
    expect(result.dig('structuredContent', 'items').map { |item| item['id'] }).to eq([label.to_global_id.to_s])
  end

  it 'advertises both input shapes in the latest tool schema' do
    post api('/mcp', user, oauth_access_token: access_token),
      params: { jsonrpc: '2.0', method: 'tools/list', id: '1' }

    expect(response).to have_gitlab_http_status(:ok)
    search_tool = json_response.dig('result', 'tools').find { |tool| tool['name'] == 'search_labels' }
    expect(search_tool.dig('inputSchema', 'properties', 'search', 'oneOf')).to eq([
      { 'type' => 'string' },
      { 'type' => 'array', 'items' => { 'type' => 'string' }, 'minItems' => 1, 'maxItems' => 10 }
    ])
  end

  it 'rejects a non-string scalar search term' do
    result = call_search(3)

    expect(result['isError']).to be(true)
    expect(result['content'].first['text']).to include('search is invalid')
  end

  context 'when the caller cannot read the project or group' do
    let_it_be(:private_project) { create(:project, :private) }
    let_it_be(:private_group) { create(:group, :private) }

    before_all do
      create(:label, project: private_project, title: 'hidden-bug')
      create(:group_label, group: private_group, title: 'hidden-group-bug')
    end

    def call_with(arguments)
      post api('/mcp', user, oauth_access_token: access_token), params: {
        jsonrpc: '2.0', method: 'tools/call', id: '1',
        params: { name: 'search_labels', arguments: arguments }
      }, as: :json

      expect(response).to have_gitlab_http_status(:ok)
      json_response.fetch('result')
    end

    it 'answers a private project_id the same way as a missing one' do
      result = call_with(project_id: private_project.id.to_s, search: 'bug')

      expect(result['isError']).to be(true)
      expect(result.dig('content', 0, 'text')).to eq("Project '#{private_project.id}' not found or inaccessible")
      expect(result.to_json).not_to include(private_project.full_path, 'hidden-bug')
    end

    it 'answers a private group_id the same way as a missing one' do
      result = call_with(group_id: private_group.id.to_s, search: 'bug')

      expect(result['isError']).to be(true)
      expect(result.dig('content', 0, 'text')).to eq("Group '#{private_group.id}' not found or inaccessible")
      expect(result.to_json).not_to include(private_group.full_path, 'hidden-group-bug')
    end
  end
end
