# frozen_string_literal: true

require "spec_helper"

RSpec.describe API::Mcp::Handlers::PingRequest, feature_category: :mcp_server do
  let_it_be(:user) { create(:user) }
  let_it_be(:access_token) { create(:oauth_access_token, user: user, scopes: [:mcp]) }

  before do
    stub_application_setting(instance_level_ai_beta_features_enabled: true)
  end

  describe 'POST /mcp with ping method' do
    it 'returns an empty result', :aggregate_failures do
      post api('/mcp', user, oauth_access_token: access_token),
        params: { jsonrpc: '2.0', method: 'ping', id: '1' }

      expect(response).to have_gitlab_http_status(:ok)
      expect(json_response).to eq('jsonrpc' => '2.0', 'id' => '1', 'result' => {})
    end
  end
end
