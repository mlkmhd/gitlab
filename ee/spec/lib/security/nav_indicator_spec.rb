# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Security::NavIndicator, feature_category: :security_testing_configuration do
  let_it_be(:group) { create(:group) }

  # Not let_it_be: User#callouts_by_feature_name is memoized on the instance.
  let(:user) { create(:user, maintainer_of: group) }

  let(:page) { :configuration }

  subject(:visible) { described_class.visible?(user: user, namespace: group, page: page) }

  before do
    stub_licensed_features(security_scan_profiles: true)
  end

  context 'on a date before the indicator expires' do
    around do |example|
      travel_to(described_class::EXPIRES_ON - 1.day) { example.run }
    end

    it { is_expected.to be(true) }

    context 'when the user cannot apply security scan profiles' do
      let(:user) { create(:user, developer_of: group) }

      it { is_expected.to be(false) }
    end

    context 'when security scan profiles are not licensed' do
      before do
        stub_licensed_features(security_scan_profiles: false)
      end

      it { is_expected.to be(false) }
    end

    context 'when there is no user' do
      let(:user) { nil }

      it { is_expected.to be(false) }
    end

    context 'when the feature flag is disabled' do
      before do
        stub_feature_flags(security_nav_indicator: false)
      end

      it { is_expected.to be(false) }
    end

    context 'when the feature flag is enabled only for another group' do
      before do
        stub_feature_flags(security_nav_indicator: create(:group))
      end

      it { is_expected.to be(false) }
    end

    context 'when the namespace is a subgroup of the group the flag is enabled for' do
      let_it_be(:subgroup) { create(:group, parent: group) }

      before do
        stub_feature_flags(security_nav_indicator: group)
      end

      it 'checks the flag against the root ancestor' do
        expect(described_class.visible?(user: user, namespace: subgroup, page: page)).to be(true)
      end
    end

    described_class::CALLOUT_FEATURE_NAMES.each do |callout_page, feature_name|
      context "for the #{callout_page} page" do
        let(:page) { callout_page }

        it 'is hidden once that page callout is dismissed' do
          create(:callout, user: user, feature_name: feature_name)

          expect(visible).to be(false)
        end

        it 'stays visible when only another page callout is dismissed' do
          other_feature_name = (described_class::CALLOUT_FEATURE_NAMES.values - [feature_name]).first
          create(:callout, user: user, feature_name: other_feature_name)

          expect(visible).to be(true)
        end
      end
    end
  end

  context 'when the indicator has expired' do
    around do |example|
      travel_to(described_class::EXPIRES_ON + 1.day) { example.run }
    end

    it { is_expected.to be(false) }
  end

  context 'on the last day of the indicator' do
    around do |example|
      travel_to(described_class::EXPIRES_ON) { example.run }
    end

    it { is_expected.to be(true) }
  end
end
