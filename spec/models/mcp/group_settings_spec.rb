# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Mcp::GroupSettings, feature_category: :mcp_server do
  describe '#setting_available?' do
    it 'returns false in FOSS' do
      expect(described_class.new(build_stubbed(:group)).setting_available?).to be(false)
    end
  end

  describe '#mcp_server_enabled?' do
    subject(:settings) { described_class.new(group) }

    context 'when group is root' do
      let_it_be_with_reload(:group) { create(:group) }

      it 'returns true when namespace_settings has mcp_server_enabled set to true' do
        group.namespace_settings.update!(mcp_server_enabled: true)

        expect(settings.mcp_server_enabled?).to be true
      end

      it 'returns false when namespace_settings has mcp_server_enabled set to false' do
        group.namespace_settings.update!(mcp_server_enabled: false)

        expect(settings.mcp_server_enabled?).to be false
      end
    end

    context 'when a root group has just been created' do
      let_it_be(:group) { create(:group) }

      it 'is enabled without the owner opting in' do
        expect(settings.mcp_server_enabled?).to be true
      end
    end

    context 'when group is a subgroup' do
      let(:group) { build(:group, parent: build(:group)) }

      it { expect(settings.mcp_server_enabled?).to be false }
    end

    context 'when namespace_settings is nil' do
      let(:group) { build(:group) }

      before do
        allow(group).to receive(:namespace_settings).and_return(nil)
      end

      it { expect(settings.mcp_server_enabled?).to be false }
    end
  end
end
