# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Onboarding::FeatureLibrary::ExplorePagesBuilder, feature_category: :onboarding do
  describe 'page copy' do
    let(:user) { build_stubbed(:user) }
    let(:group) { build_stubbed(:group) }

    let(:plan_context) do
      instance_double(
        Onboarding::FeatureLibrary::CurrentPlanContext,
        to_h: { edition: :ee, deployment: :saas, current_plan: :free, base_plan: :free, trial: false },
        tier_pages: %i[premium ultimate],
        base_plan: :free,
        deployment: :saas
      )
    end

    subject(:pages) { described_class.new(user: user, resource: group, panel: 'group').execute[:pages] }

    before do
      allow(Onboarding::FeatureLibrary::CurrentPlanContext).to receive(:new).with(resource: group)
        .and_return(plan_context)
      allow(Onboarding::FeatureLibrary::UpgradeCta).to receive(:new)
        .and_return(instance_double(Onboarding::FeatureLibrary::UpgradeCta, build: nil))
    end

    it 'has page copy for every plan above Free' do
      expect(described_class::PAGE_COPY.keys).to eq(Onboarding::FeatureLibrary::CurrentPlanContext::PLANS - [:free])
    end

    it 'gives each page its title and subtitle' do
      expect(pages.map { |page| page.slice(:plan, :title, :subtitle) }).to eq([
        {
          plan: :premium,
          title: s_('FeatureLibrary|Explore Premium features'),
          subtitle: s_('FeatureLibrary|Control merges and plan work across teams')
        },
        {
          plan: :ultimate,
          title: s_('FeatureLibrary|Explore Ultimate features'),
          subtitle: s_('FeatureLibrary|All of Premium, plus security, analytics, and more')
        }
      ])
    end

    it 'adds the label text to each item' do
      items = pages.flat_map { |page| page[:credits] + page[:categories].flat_map { |category| category[:items] } }

      expect(items.pluck(:label)).to include(
        { type: 'new', plan: :premium, text: s_('FeatureLibrary|New with Premium') },
        { type: 'enhanced', plan: :ultimate, text: s_('FeatureLibrary|Enhanced with Ultimate') },
        { type: 'add_on', plan: :premium, text: s_('FeatureLibrary|Add-on') }
      )
    end

    it 'gives each page its section titles' do
      expect(pages.map { |page| page.slice(:highlights_title, :credits_title) }).to eq([
        {
          highlights_title: s_('FeatureLibrary|Premium highlights'),
          credits_title: s_('FeatureLibrary|Powered by GitLab Credits')
        },
        {
          highlights_title: s_('FeatureLibrary|Ultimate highlights'),
          credits_title: s_('FeatureLibrary|Powered by GitLab Credits')
        }
      ])
    end
  end

  describe '.available?' do
    using RSpec::Parameterized::TableSyntax

    let_it_be(:member) { create(:user) }
    let_it_be(:non_member) { create(:user) }
    let_it_be(:admin) { create(:admin) }
    let_it_be(:root_group) { create(:group, :public, guests: member) }
    let_it_be(:subgroup) { create(:group, :public, parent: root_group) }

    subject(:available) { described_class.available?(user: viewer, resource: resource) }

    where(:viewer, :resource, :expected) do
      ref(:member)     | ref(:root_group) | true
      ref(:non_member) | ref(:root_group) | false
      ref(:admin)      | ref(:root_group) | false
      nil              | ref(:root_group) | false
      ref(:member)     | nil              | false
    end

    with_them do
      it { is_expected.to be(expected) }
    end

    context 'when the admin is in admin mode', :enable_admin_mode do
      let(:viewer) { admin }
      let(:resource) { root_group }

      it { is_expected.to be(true) }
    end

    context 'when the flag is enabled for the root group only' do
      let(:viewer) { member }

      before do
        stub_feature_flags(feature_catalog_explore_pages: root_group)
      end

      context 'with a subgroup' do
        let(:resource) { subgroup }

        it { is_expected.to be(true) }
      end

      context 'with another root group' do
        let(:resource) { create(:group, :public, guests: member) }

        it { is_expected.to be(false) }
      end
    end

    context 'when the flag is disabled' do
      let(:viewer) { member }
      let(:resource) { root_group }

      before do
        stub_feature_flags(feature_catalog_explore_pages: false)
      end

      it { is_expected.to be(false) }
    end

    context 'on GitLab.com', :saas_gitlab_com_subscriptions do
      let(:viewer) { member }
      let(:resource) { subgroup }

      where(:subscription, :expected) do
        nil                    | true
        :premium               | true
        :ultimate              | false
        :ultimate_trial        | true
      end

      with_them do
        before do
          create(:gitlab_subscription, subscription, namespace: root_group) if subscription
        end

        it { is_expected.to be(expected) }
      end

      it 'reuses a plan already loaded in the request', :request_store do
        root_group.actual_plan

        queries = ActiveRecord::QueryRecorder.new do
          ::Onboarding::FeatureLibrary::CurrentPlanContext.new(resource: resource).has_upgrade_pages?
        end

        expect(queries.count).to eq(0)
      end
    end

    context 'on self-managed with an Ultimate trial license' do
      let(:viewer) { member }
      let(:resource) { root_group }
      let(:trial_license) { build_stubbed(:license, plan: License::ULTIMATE_PLAN) }

      before do
        allow(trial_license).to receive_messages(trial?: true, expired?: false)
        allow(License).to receive(:current).and_return(trial_license)
      end

      it 'is available without looking up the paid license' do
        expect(License).not_to receive(:billable_license)

        expect(available).to be(true)
      end
    end
  end
end
