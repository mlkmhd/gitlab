# frozen_string_literal: true

require 'spec_helper'

RSpec.describe ClickHouse::QueryLimiting::Rules::GuestWebRequest, feature_category: :database do
  describe '.applies?' do
    let(:user) { build_stubbed(:user) }
    let(:puma) { true }

    subject(:applies) { described_class.applies?(Labkit::Context.current) }

    before do
      allow(Gitlab::Runtime).to receive(:puma?).and_return(puma)
    end

    it 'applies to guest web requests' do
      expect(applies).to be(true)
    end

    it 'does not apply when a user is present' do
      Gitlab::ApplicationContext.with_context(user: user) do
        expect(applies).to be(false)
      end
    end

    context 'when the process is not puma' do
      let(:puma) { false }

      it { is_expected.to be(false) }
    end

    context 'when click_house_guest_query_limits is disabled' do
      before do
        stub_feature_flags(click_house_guest_query_limits: false)
      end

      it { is_expected.to be(false) }
    end

    it 'applies when there is no context' do
      expect(described_class.applies?(nil)).to be(true)
    end
  end
end
