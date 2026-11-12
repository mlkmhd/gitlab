# frozen_string_literal: true

module EE
  module Mcp
    module GroupSettings
      extend ::Gitlab::Utils::Override

      override :setting_available?
      def setting_available?
        group.root? && ::Gitlab::Saas.feature_available?(:mcp_server_saas_only)
      end
    end
  end
end
