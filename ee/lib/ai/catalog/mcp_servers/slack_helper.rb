# frozen_string_literal: true

module Ai
  module Catalog
    module McpServers
      module SlackHelper
        extend self

        MCP_URL = 'https://mcp.slack.com/mcp'

        # Keep in sync with `pre_approved_tools` in the ai-assist `slack_assistant` flow config.
        PRE_APPROVED_TOOLS = %w[
          slack_slack_search_public
          slack_slack_search_channels
          slack_slack_read_channel
          slack_slack_read_thread
        ].freeze

        def gitlab_slack_app_server(organization)
          slack_app_id = Gitlab::CurrentSettings.slack_app_id
          return if slack_app_id.blank?

          ::Ai::Catalog::McpServer.in_organization(organization).find_by_url_and_oauth_client_xid(MCP_URL, slack_app_id)
        end

        # The flag is checked here too because users who can read the catalog pass the policy without it.
        def gitlab_slack_app_server_for(user, organization)
          return unless ::Feature.enabled?(:slack_duo_mcp_server, user)

          mcp_server = gitlab_slack_app_server(organization)
          mcp_server if mcp_server && Ability.allowed?(user, :read_ai_catalog_mcp_server, mcp_server)
        end

        def gitlab_slack_app_server?(mcp_server)
          slack_app_id = Gitlab::CurrentSettings.slack_app_id

          slack_app_id.present? && mcp_server.url == MCP_URL && mcp_server.oauth_client_id == slack_app_id
        end
      end
    end
  end
end
