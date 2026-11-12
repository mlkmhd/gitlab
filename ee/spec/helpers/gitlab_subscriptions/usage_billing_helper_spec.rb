# frozen_string_literal: true

require 'spec_helper'

RSpec.describe GitlabSubscriptions::UsageBillingHelper, feature_category: :consumables_cost_management do
  let(:group) { build_stubbed(:group) }
  let(:plan_name_for_upgrading) { ::GitlabSubscriptions::SystemDefined::Plan::FREE }
  let(:has_gitlab_credits) { false }

  before do
    allow(group).to receive_messages(plan_name_for_upgrading: plan_name_for_upgrading)
    allow(group).to receive(:has_active_add_on_purchase?).with(:gitlab_credits).and_return(has_gitlab_credits)
  end

  describe '#free_namespace?' do
    subject { helper.free_namespace?(group) }

    context 'when the namespace is on the free plan' do
      it { is_expected.to be(true) }

      context 'with an active gitlab_credits add-on purchase' do
        let(:has_gitlab_credits) { true }

        it { is_expected.to be(false) }
      end
    end

    context 'when the namespace is on a paid plan' do
      let(:plan_name_for_upgrading) { ::GitlabSubscriptions::SystemDefined::Plan::PREMIUM }

      it { is_expected.to be(false) }
    end
  end
end
