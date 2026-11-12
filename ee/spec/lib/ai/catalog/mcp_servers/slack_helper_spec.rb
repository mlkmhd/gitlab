# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Ai::Catalog::McpServers::SlackHelper, feature_category: :duo_agent_platform do
  describe '.gitlab_slack_app_server' do
    let_it_be(:organization) { create(:organization) }
    let_it_be(:mcp_server) do
      create(:ai_catalog_mcp_server, :with_oauth,
        organization: organization, url: described_class::MCP_URL, oauth_client_id: 'gitlab-slack-app-id')
    end

    let(:lookup_organization) { organization }

    subject(:server) { described_class.gitlab_slack_app_server(lookup_organization) }

    before do
      stub_application_setting(slack_app_id: 'gitlab-slack-app-id')
    end

    it 'returns the organization MCP server that uses the GitLab for Slack app' do
      expect(server).to eq(mcp_server)
    end

    context 'when another MCP server uses the same client ID at a different URL' do
      before_all do
        create(:ai_catalog_mcp_server, :with_oauth,
          organization: organization, url: 'https://attacker.example.com/mcp', oauth_client_id: 'gitlab-slack-app-id')
      end

      it 'returns only the MCP server at the Slack MCP URL' do
        expect(server).to eq(mcp_server)
      end
    end

    context 'when the only MCP server with the client ID is not at the Slack MCP URL' do
      let_it_be(:lookup_organization) { create(:organization) }

      before_all do
        create(:ai_catalog_mcp_server, :with_oauth,
          organization: lookup_organization, url: 'https://attacker.example.com/mcp',
          oauth_client_id: 'gitlab-slack-app-id')
      end

      it { is_expected.to be_nil }
    end

    context 'when the MCP server belongs to another organization' do
      let(:lookup_organization) { create(:organization) }

      it { is_expected.to be_nil }
    end

    context 'when the MCP server uses another Slack app' do
      before do
        stub_application_setting(slack_app_id: 'other-slack-app-id')
      end

      it { is_expected.to be_nil }
    end

    context 'when the instance has no GitLab for Slack app configured' do
      before do
        stub_application_setting(slack_app_id: nil)
      end

      it { is_expected.to be_nil }
    end
  end

  describe '.gitlab_slack_app_server_for' do
    let_it_be(:organization) { create(:organization) }
    let_it_be(:user) { create(:user, organizations: [organization]) }
    let_it_be(:outsider) { create(:user) }
    let_it_be(:mcp_server) do
      create(:ai_catalog_mcp_server, :with_oauth,
        organization: organization, url: described_class::MCP_URL, oauth_client_id: 'gitlab-slack-app-id')
    end

    let(:lookup_user) { user }

    subject(:server) { described_class.gitlab_slack_app_server_for(lookup_user, organization) }

    before do
      stub_application_setting(slack_app_id: 'gitlab-slack-app-id')
      allow(::Ai::Catalog).to receive(:mcp_servers_available?).and_return(false)
    end

    it 'returns the server, without AI Catalog MCP servers' do
      expect(server).to eq(mcp_server)
    end

    context 'when the user cannot read the server' do
      let(:lookup_user) { outsider }

      it { is_expected.to be_nil }
    end

    context 'when the organization has no GitLab for Slack app server' do
      subject(:server) { described_class.gitlab_slack_app_server_for(user, create(:organization)) }

      it { is_expected.to be_nil }
    end

    context 'when slack_duo_mcp_server is disabled' do
      before do
        stub_feature_flags(slack_duo_mcp_server: false)
        allow(::Ai::Catalog).to receive(:mcp_servers_available?).and_return(true)
      end

      it 'returns nothing, even when the user can read the AI Catalog' do
        expect(server).to be_nil
      end
    end
  end

  describe '.gitlab_slack_app_server?' do
    let(:mcp_server) { build(:ai_catalog_mcp_server, url: url, oauth_client_id: oauth_client_id) }
    let(:url) { described_class::MCP_URL }
    let(:oauth_client_id) { 'gitlab-slack-app-id' }

    subject { described_class.gitlab_slack_app_server?(mcp_server) }

    before do
      stub_application_setting(slack_app_id: 'gitlab-slack-app-id')
    end

    it { is_expected.to be(true) }

    context 'when the MCP server is not at the Slack MCP URL' do
      let(:url) { 'https://attacker.example.com/mcp' }

      it { is_expected.to be(false) }
    end

    context 'when the MCP server uses another Slack app' do
      let(:oauth_client_id) { 'other-slack-app-id' }

      it { is_expected.to be(false) }
    end

    context 'when neither the instance nor the MCP server has a client ID' do
      let(:oauth_client_id) { nil }

      before do
        stub_application_setting(slack_app_id: nil)
      end

      it { is_expected.to be(false) }
    end
  end
end
