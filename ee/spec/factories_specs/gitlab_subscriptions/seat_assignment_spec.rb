# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'GitlabSubscriptions::SeatAssignment factory', feature_category: :seat_cost_management do
  describe 'organization' do
    context 'when a namespace is set' do
      let_it_be(:organization) { create(:organization) }
      let_it_be(:group) { create(:group, organization: organization) }

      subject(:seat_assignment) { build(:gitlab_subscription_seat_assignment, namespace: group) }

      it 'uses the organization of the namespace' do
        expect(seat_assignment.organization).to eq(organization)
      end
    end

    context 'when the namespace is nil' do
      subject(:seat_assignment) { build(:gitlab_subscription_seat_assignment, namespace: nil) }

      it 'uses the common organization' do
        expect(seat_assignment.organization).to eq(create(:common_organization))
      end
    end
  end
end
