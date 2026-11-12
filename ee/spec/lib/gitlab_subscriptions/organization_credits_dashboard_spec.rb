# frozen_string_literal: true

require 'spec_helper'

RSpec.describe GitlabSubscriptions::OrganizationCreditsDashboard, :saas, feature_category: :consumables_cost_management do
  describe '.path_for' do
    let_it_be(:organization) { create(:organization) }
    let_it_be(:organization_gitlab_subscription) do
      create(:organization_gitlab_subscription, organization: organization)
    end

    let_it_be(:group) { create(:group, organization: organization) }
    let_it_be(:organization_owner) { create(:user, owner_of: organization) }
    let_it_be(:group_owner) { create(:user, owner_of: group) }

    subject(:path) { described_class.path_for(group, user) }

    context 'when the user can read the Organization credits page' do
      let(:user) { organization_owner }

      it { is_expected.to eq("/o/#{organization.path}/-/gitlab_credits_dashboard") }

      context 'when organization_billing is disabled' do
        before do
          stub_feature_flags(organization_billing: false)
        end

        it { is_expected.to be_nil }
      end
    end

    context 'when the user cannot read the Organization credits page' do
      let(:user) { group_owner }

      it { is_expected.to be_nil }
    end

    context 'when there is no user' do
      let(:user) { nil }

      it { is_expected.to be_nil }
    end

    context 'when the group is in the default Organization' do
      let_it_be(:group) { create(:group) }
      let(:user) { organization_owner }

      it { is_expected.to be_nil }
    end
  end
end
