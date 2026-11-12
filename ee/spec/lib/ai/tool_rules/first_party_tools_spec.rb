# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Ai::ToolRules::FirstPartyTools, feature_category: :duo_agent_platform do
  let_it_be(:root_group) { create(:group) }
  let_it_be(:subgroup) { create(:group, parent: root_group) }
  let_it_be(:other_root_group) { create(:group) }

  before do
    stub_feature_flags(duo_cli_first_party_tools: root_group)
  end

  describe '.for' do
    it 'lists the first-party tools for the root group the flag is enabled for' do
      expect(described_class.for(root_group).names).to eq(Ai::ToolRules::Registry::FIRST_PARTY_CLIENT_TOOLS.keys)
    end

    it 'checks the flag against the root group, not the namespace passed in' do
      expect(described_class.for(subgroup).names).to eq(Ai::ToolRules::Registry::FIRST_PARTY_CLIENT_TOOLS.keys)
    end

    it 'lists nothing for another root group, or without a namespace', :aggregate_failures do
      expect(described_class.for(other_root_group)).to be_empty
      expect(described_class.for(nil)).to be_empty
    end
  end

  describe '#include?' do
    it 'matches exact names only', :aggregate_failures do
      tools = described_class.for(root_group)

      expect(tools.include?('mcp__duo__review')).to be(true)
      expect(tools.include?('mcp__duo..review')).to be(false)
    end
  end
end
