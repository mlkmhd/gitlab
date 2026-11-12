# frozen_string_literal: true

require 'spec_helper'

RSpec.describe GitlabSubscriptions::OrganizationBilling, :saas, feature_category: :consumables_cost_management do
  describe '.active?' do
    let_it_be_with_reload(:organization) { create(:organization) }

    subject { described_class.active?(organization) }

    before do
      stub_ee_application_setting(should_check_namespace_plan: true)
    end

    def nominate(namespace, plan: :ultimate)
      create(:organization_gitlab_subscription, organization: organization,
        gitlab_subscription: create(:gitlab_subscription, plan, namespace: namespace))
    end

    context 'when an entitled group in the organization is nominated' do
      before do
        nominate(create(:group, organization: organization))
      end

      it { is_expected.to be(true) }

      context 'when organization_billing is disabled' do
        before do
          stub_feature_flags(organization_billing: false)
        end

        it { is_expected.to be(false) }
      end
    end

    context 'when the nominated group is not entitled to GitLab Credits' do
      before do
        nominate(create(:group, organization: organization), plan: :free)
      end

      it { is_expected.to be(false) }
    end

    context 'when the nominated group belongs to another organization' do
      before do
        nominate(create(:group, organization: create(:organization)))
      end

      it { is_expected.to be(false) }
    end

    context 'when the nominated namespace is a personal namespace' do
      before do
        nominate(create(:user_namespace, organization: organization))
      end

      it { is_expected.to be(false) }
    end

    context 'when the organization is not linked to a subscription' do
      it { is_expected.to be(false) }
    end
  end
end
