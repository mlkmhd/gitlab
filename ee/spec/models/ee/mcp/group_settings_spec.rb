# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Mcp::GroupSettings, feature_category: :mcp_server do
  describe '#setting_available?' do
    let_it_be(:group) { create(:group) }
    let_it_be(:subgroup) { create(:group, parent: group) }

    context 'when on GitLab.com', :saas do
      it { expect(described_class.new(group).setting_available?).to be(true) }
      it { expect(described_class.new(subgroup).setting_available?).to be(false) }
    end

    context 'when self-managed' do
      it { expect(described_class.new(group).setting_available?).to be(false) }
    end
  end
end
