# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'MCP tool annotation declarations', feature_category: :ai_agents do
  let(:manager) { Mcp::Tools::Manager.new }

  describe 'every registered tool declares a readOnlyHint annotation' do
    it 'has no tools missing readOnlyHint' do
      offenders = manager.tools.reject { |_name, tool| tool.annotations.key?(:readOnlyHint) }.keys

      expect(offenders).to be_empty,
        "Tools missing a readOnlyHint annotation: #{offenders}. Add `readOnlyHint` to register_version " \
          "annotations (service classes) or route_setting :mcp annotations (API routes)."
    end
  end

  describe 'every registered tool declares title, idempotentHint, and openWorldHint annotations' do
    it 'has no tools missing title, idempotentHint, or openWorldHint' do
      booleans = [true, false].freeze
      offenders = manager.tools.each_with_object({}) do |(name, tool), missing|
        annotations = tool.annotations
        missing_keys = []
        missing_keys << :title unless annotations[:title].is_a?(String) && annotations[:title].present?
        missing_keys << :idempotentHint unless booleans.include?(annotations[:idempotentHint])
        missing_keys << :openWorldHint unless booleans.include?(annotations[:openWorldHint])

        missing[name] = missing_keys if missing_keys.any?
      end

      expect(offenders).to be_empty,
        "Tools missing annotations: " \
          "#{offenders.map { |name, keys| "#{name} (#{keys.join(', ')})" }.join('; ')}. " \
          "Add `title`, `idempotentHint`, and `openWorldHint` to register_version annotations (service classes) " \
          "or route_setting :mcp annotations (API routes)."
    end
  end
end
