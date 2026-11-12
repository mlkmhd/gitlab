# frozen_string_literal: true

module Ai
  module Catalog
    module McpServers
      class SlackConfigService
        include Gitlab::Utils::StrongMemoize
        include AuthHeaders

        SERVER_KEY = :slack

        def initialize(current_user, namespace:)
          @current_user = current_user
          @namespace = namespace
        end

        def execute
          return {} unless namespace && mcp_server && mcp_servers_user
          return {} if blocked?

          # Trusted like GitLab MCP and Orbit, so DWS runs it without "Allow external MCP tools" until tools carry
          # an origin: https://gitlab.com/gitlab-org/gitlab/-/work_items/635112
          {
            SERVER_KEY => {
              URL: mcp_server.url,
              Headers: build_mcp_server_headers(mcp_server, mcp_servers_user),
              Trusted: true
            }
          }
        end

        private

        attr_reader :current_user, :namespace

        def mcp_server
          ::Ai::Catalog::McpServers::SlackHelper.gitlab_slack_app_server_for(current_user, namespace.organization)
        end
        strong_memoize_attr :mcp_server

        def mcp_servers_user
          mcp_server.mcp_servers_users.find_by_user_id(current_user.id)
        end
        strong_memoize_attr :mcp_servers_user

        def blocked?
          return false unless Feature.enabled?(:mcp_server_block_enforcement, namespace.root_ancestor)

          ::Ai::Catalog::McpServerBlock.blocked_server_ids_for(namespace, [mcp_server.id]).exists?
        end
      end
    end
  end
end
