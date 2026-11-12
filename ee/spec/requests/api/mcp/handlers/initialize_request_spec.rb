# frozen_string_literal: true

require "spec_helper"

RSpec.describe API::Mcp::Handlers::InitializeRequest, feature_category: :mcp_server do
  let_it_be(:user) { create(:user) }
  let_it_be(:access_token) { create(:oauth_access_token, user: user, scopes: [:mcp]) }

  let(:instructions) { EE::API::Mcp::Handlers::InitializeRequest::DAP_FLOW_INSTRUCTIONS }
  let(:logger) { instance_double(Gitlab::Mcp::Logger, conditional_info: nil) }

  before do
    stub_application_setting(instance_level_ai_beta_features_enabled: true)
    stub_licensed_features(ai_workflows: true)
    ::Ai::Setting.for_organization(user.organization)
      .update!(feature_settings: { duo_agent_platform_enabled: true })
  end

  def post_initialize(protocol_version = '2025-11-25')
    post api('/mcp', user, oauth_access_token: access_token),
      params: { jsonrpc: '2.0', method: 'initialize', id: '1', params: { protocolVersion: protocol_version } }
  end

  shared_examples 'sends no server instructions' do
    it 'leaves instructions out of the result and logs that none were sent', :aggregate_failures do
      allow(Gitlab::Mcp::Logger).to receive(:build).and_return(logger)

      post_initialize

      expect(response).to have_gitlab_http_status(:ok)
      expect(json_response['result']).not_to have_key('instructions')
      expect(logger).to have_received(:conditional_info).with(
        user, hash_including(event_name: 'initialize', server_instructions_sent: false)
      )
    end
  end

  it 'keeps the instructions under the 2,048 characters some clients truncate at' do
    expect(instructions.length).to be < 2048
  end

  context 'when the user can use the GitLab Duo Agent Platform' do
    before do
      purchase = create(:gitlab_subscription_add_on_purchase, :self_managed, :duo_enterprise)
      create(:gitlab_subscription_user_add_on_assignment, user: user, add_on_purchase: purchase)
    end

    it 'sends the GitLab Duo flow instructions and logs that they were sent', :aggregate_failures do
      allow(Gitlab::Mcp::Logger).to receive(:build).and_return(logger)

      post_initialize

      expect(response).to have_gitlab_http_status(:ok)
      expect(json_response['result']['instructions']).to eq(instructions)
      expect(logger).to have_received(:conditional_info).with(
        user, hash_including(event_name: 'initialize', server_instructions_sent: true)
      )
    end

    API::Mcp::Handlers::InitializeRequest::SUPPORTED_PROTOCOL_VERSIONS.each do |version|
      it "sends them for protocol version #{version}" do
        post_initialize(version)

        expect(response).to have_gitlab_http_status(:ok)
        expect(json_response['result']['instructions']).to eq(instructions)
      end
    end

    context 'when GitLab Duo is set to Always off' do
      before do
        stub_application_setting(duo_features_enabled: false, lock_duo_features_enabled: true)
      end

      it_behaves_like 'sends no server instructions'
    end

    context 'when the user is not allowed to use the GitLab Duo Agent Platform' do
      before do
        create(:ai_instance_accessible_entity_rules, :duo_agent_platform)
      end

      it_behaves_like 'sends no server instructions'
    end

    context 'when there is neither an ai_workflows license nor self-managed GitLab credits' do
      before do
        stub_licensed_features(ai_workflows: false)
      end

      it_behaves_like 'sends no server instructions'
    end
  end
end
