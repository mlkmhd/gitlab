# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Organizations::GitlabCreditsDashboardHelper, :saas, feature_category: :consumables_cost_management do
  let(:organization) { build_stubbed(:organization) }
  let(:subscription) { build_stubbed(:gitlab_subscription, plan_code: Plan::ULTIMATE, start_date: Date.new(2026, 10, 1)) }
  let(:nominated_group) { build_stubbed(:group, gitlab_subscription: subscription) }

  before do
    allow(organization).to receive(:billing_namespace).and_return(nominated_group)
  end

  describe '#organization_usage_billing_dashboard_data' do
    subject(:data) { helper.organization_usage_billing_dashboard_data(organization) }

    it 'returns the subscription data and nothing that names the nominated group' do
      expect(data).to eq(
        organization_id: organization.to_global_id.to_s,
        subscription_start_date: '2026-10-01',
        is_saas: 'true',
        is_free: 'false',
        is_paid_base_plan: 'true',
        credits_generalization_ui: 'true'
      )
    end

    context 'when the subscription has no start date' do
      let(:subscription) { build_stubbed(:gitlab_subscription, start_date: nil) }

      it { is_expected.to include(subscription_start_date: nil) }
    end

    context 'when the nominated group is on the free plan without GitLab Credits' do
      let(:subscription) { build_stubbed(:gitlab_subscription, :free) }

      it { is_expected.to include(is_free: 'true') }
    end

    context 'when the credits_generalization_ui feature flag is disabled' do
      before do
        stub_feature_flags(credits_generalization_ui: false)
      end

      it { is_expected.to include(credits_generalization_ui: 'false') }
    end
  end
end
