# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Ai::Catalog::McpServerPolicy, feature_category: :workflow_catalog do
  let_it_be(:organization) { create(:organization) }
  let_it_be(:organization_user) { create(:user, organizations: [organization]) }
  let_it_be(:other_user) { create(:user) }
  let_it_be(:admin) { create(:admin) }

  let_it_be(:slack_server) do
    create(:ai_catalog_mcp_server, :with_oauth, organization: organization,
      url: Ai::Catalog::McpServers::SlackHelper::MCP_URL, oauth_client_id: 'gitlab-slack-app-id')
  end

  let_it_be(:other_server) { create(:ai_catalog_mcp_server, organization: organization) }

  let(:user) { organization_user }
  let(:mcp_servers_available) { true }

  subject(:policy) { described_class.new(user, mcp_server) }

  before do
    stub_application_setting(slack_app_id: 'gitlab-slack-app-id')
    allow(::Ai::Catalog).to receive(:mcp_servers_available?).and_return(mcp_servers_available)
  end

  it { expect(described_class).to delegate_to(::Organizations::OrganizationPolicy) }

  describe 'read_ai_catalog_mcp_server' do
    context 'with another server' do
      let(:mcp_server) { other_server }

      it { expect_allowed(:read_ai_catalog_mcp_server) }

      context 'when AI Catalog MCP servers are not available to the user' do
        let(:mcp_servers_available) { false }

        it { expect_disallowed(:read_ai_catalog_mcp_server) }
      end
    end

    context 'with the GitLab for Slack app server' do
      let(:mcp_server) { slack_server }

      it { expect_allowed(:read_ai_catalog_mcp_server) }

      context 'when slack_duo_mcp_server is disabled' do
        before do
          stub_feature_flags(slack_duo_mcp_server: false)
        end

        it 'still follows the organization' do
          expect_allowed(:read_ai_catalog_mcp_server)
        end
      end

      context 'when AI Catalog MCP servers are not available to the user' do
        let(:mcp_servers_available) { false }

        it { expect_allowed(:read_ai_catalog_mcp_server) }

        context 'when the user is not in the organization' do
          let(:user) { other_user }

          it { expect_disallowed(:read_ai_catalog_mcp_server) }
        end

        context 'when the user is an admin outside the organization' do
          let(:user) { admin }

          context 'when admin mode is enabled', :enable_admin_mode do
            it { expect_disallowed(:read_ai_catalog_mcp_server) }
          end

          context 'when admin mode is disabled' do
            it { expect_disallowed(:read_ai_catalog_mcp_server) }
          end
        end

        context 'when slack_duo_mcp_server is disabled' do
          before do
            stub_feature_flags(slack_duo_mcp_server: false)
          end

          it { expect_disallowed(:read_ai_catalog_mcp_server) }
        end

        context 'when the server uses another Slack app' do
          before do
            stub_application_setting(slack_app_id: 'another-app-id')
          end

          it { expect_disallowed(:read_ai_catalog_mcp_server) }
        end
      end
    end
  end
end
