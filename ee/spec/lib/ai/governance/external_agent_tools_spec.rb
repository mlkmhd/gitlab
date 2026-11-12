# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Ai::Governance::ExternalAgentTools, feature_category: :compliance_management do
  describe '.tools' do
    subject(:tools) { described_class.tools }

    it 'is keyed by agent types the GitLab CLI can register', :aggregate_failures do
      expect(tools.keys).to all(be_in(::Ai::ExternalAgents::AgentIdentity::AGENT_TYPES))
      expect(tools.keys).to match_array(%w[claude-code cursor codex opencode])
    end

    it 'groups each agent by privilege groups the tool registry maps to an action type' do
      groups = ::Ai::ToolRules::Registry::ACTION_TYPE_GROUPS.values.flatten.map(&:to_s)

      expect(tools.values.flat_map(&:keys)).to all(be_in(groups))
    end
  end

  describe '.rows' do
    subject(:rows) { described_class.rows }

    it 'records the vendor docs and where each name was seen' do
      expect(rows).to all(include(docs: a_string_starting_with('https://'), seen_in: be_present))
    end

    it 'lists each agent and tool pair once', :aggregate_failures do
      pairs = rows.map { |row| row.values_at(:agent_type, :name) }

      expect(pairs).to eq(pairs.uniq)
      expect(rows.size).to eq(12)
    end
  end

  describe '.action_type_of' do
    it 'returns the action type of the group the pair belongs to', :aggregate_failures do
      expect(described_class.action_type_of('claude-code', 'Read')).to eq(:read)
      expect(described_class.action_type_of('cursor', 'Write')).to eq(:write)
      expect(described_class.action_type_of('codex', 'exec')).to eq(:destroy)
    end

    it 'is nil for a pair that is not on the list', :aggregate_failures do
      # Codex has no Read tool, so the same name means nothing there.
      expect(described_class.action_type_of('codex', 'Read')).to be_nil
      # Network tools stay Unclassified on purpose.
      expect(described_class.action_type_of('claude-code', 'WebFetch')).to be_nil
      expect(described_class.action_type_of(nil, 'Read')).to be_nil
    end
  end
end
