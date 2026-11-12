# frozen_string_literal: true

# Requires `nav_item` (the rendered menu item), `user` (the sidebar context
# user) and `callout_feature_name` (the callout recording the page visit).
RSpec.shared_examples 'a security nav item with the New indicator' do
  context 'on a date before the indicator expires' do
    around do |example|
      travel_to(::Security::NavIndicator::EXPIRES_ON - 1.day) { example.run }
    end

    it 'adds a "New" badge to the menu item' do
      expect(nav_item.badge).to eq({ label: 'New' })
    end

    context 'when the feature flag is disabled' do
      before do
        stub_feature_flags(security_nav_indicator: false)
      end

      it 'does not add a badge to the menu item' do
        expect(nav_item.badge).to be_nil
      end
    end

    context 'when the user has dismissed the page callout' do
      before do
        allow(user).to receive(:dismissed_callout?).and_call_original
        allow(user).to receive(:dismissed_callout?).with(feature_name: callout_feature_name).and_return(true)
      end

      it 'does not add a badge to the menu item' do
        expect(nav_item.badge).to be_nil
      end
    end
  end

  context 'when the indicator has expired' do
    around do |example|
      travel_to(::Security::NavIndicator::EXPIRES_ON + 1.day) { example.run }
    end

    it 'does not add a badge to the menu item' do
      expect(nav_item.badge).to be_nil
    end
  end
end
