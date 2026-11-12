# frozen_string_literal: true

module EE
  module Profiles
    module ChatNamesController
      extend ::Gitlab::Utils::Override

      private

      override :after_create_path
      def after_create_path(chat_name)
        mcp_server = slack_mcp_server_to_connect(chat_name)
        return super unless mcp_server

        oauth_mcp_connectors_connect_path(id: mcp_server.id, return_to: super)
      end

      def slack_mcp_server_to_connect(chat_name)
        return unless chat_name.persisted? && slack_app_params?

        ::Ai::Catalog::McpServers::SlackHelper.gitlab_slack_app_server_for(current_user, ::Current.organization)
      end
    end
  end
end
