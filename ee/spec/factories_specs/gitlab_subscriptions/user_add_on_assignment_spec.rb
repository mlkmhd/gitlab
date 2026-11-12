# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'GitlabSubscriptions::UserAddOnAssignment factory', feature_category: :seat_cost_management do
  describe 'organization' do
    context 'when an add-on purchase is set' do
      let_it_be(:organization) { create(:organization) }
      let_it_be(:add_on_purchase) do
        create(:gitlab_subscription_add_on_purchase, namespace: create(:group, organization: organization))
      end

      subject(:assignment) { build(:gitlab_subscription_user_add_on_assignment, add_on_purchase: add_on_purchase) }

      it 'uses the organization of the add-on purchase before the record is saved' do
        expect(assignment.organization).to eq(organization)
      end
    end

    context 'when the add-on purchase is nil' do
      subject(:assignment) { build(:gitlab_subscription_user_add_on_assignment, add_on_purchase: nil) }

      it 'uses the common organization' do
        expect(assignment.organization).to eq(create(:common_organization))
      end
    end
  end
end
