# frozen_string_literal: true

module Mcp
  class GroupSettings
    def initialize(group)
      @group = group
    end

    # SaaS only feature, overridden in EE
    def setting_available?
      false
    end

    def mcp_server_enabled?
      group.root? && !!group.namespace_settings&.mcp_server_enabled?
    end

    protected

    attr_reader :group
  end
end

Mcp::GroupSettings.prepend_mod
