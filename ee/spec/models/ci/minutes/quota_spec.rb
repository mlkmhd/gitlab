# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Ci::Minutes::Quota, feature_category: :hosted_runners do
  using RSpec::Parameterized::TableSyntax

  let_it_be_with_reload(:namespace) { create(:namespace) }
  let_it_be_with_reload(:another_group) { create(:group) }

  let(:quota) { described_class.new(namespace) }
  let(:namespace_monthly_quota) { 400 }
  let(:application_monthly_quota) { 400 }
  let(:purchased_minutes) { 0 }

  before do
    namespace.shared_runners_minutes_limit = namespace_monthly_quota
    namespace.extra_shared_runners_minutes_limit = purchased_minutes
    allow(::Gitlab::CurrentSettings).to receive(:shared_runners_minutes).and_return(application_monthly_quota)
  end

  describe '#enabled?' do
    subject { quota.enabled? }

    where(:namespace_monthly_quota, :application_monthly_quota, :purchased_minutes, :result) do
      0   | 100 | 0  | false
      0   | 100 | 10 | true
      nil | 100 | 10 | true
      nil | 100 | 0  | true
      20  | 100 | 0  | true
      nil | nil | 0  | false
      nil | 0   | 0  | false
    end

    with_them do
      it { is_expected.to eq(result) }

      context 'when namespace is not root' do
        before do
          namespace.parent = another_group
        end

        it { is_expected.to be(false) }
      end
    end
  end

  describe '#total' do
    subject { quota.total }

    where(:namespace_monthly_quota, :application_monthly_quota, :purchased_minutes, :result) do
      20  | 100 | 30 | 50
      nil | 100 | 30 | 130
      20  | 100 | 0  | 20
      0   | 0   | 30 | 30
      nil | 0   | 30 | 30
    end

    with_them do
      it { is_expected.to eq(result) }
    end
  end

  describe '#monthly' do
    subject { quota.monthly }

    where(:namespace_monthly_quota, :application_monthly_quota, :result) do
      20  | 100 | 20
      nil | 100 | 100
      100 | nil | 100
      0   | 100 | 0
      nil | nil | 0
    end

    with_them do
      it { is_expected.to eq(result) }
    end
  end

  describe '#purchased and #any_purchased?' do
    where(:purchased_minutes, :purchased, :any_purchased) do
      nil | 0  | false
      0   | 0  | false
      10  | 10 | true
    end

    with_them do
      it 'returns the purchased minutes and whether any were purchased' do
        expect(quota.purchased).to eq(purchased)
        expect(quota.any_purchased?).to eq(any_purchased)
      end
    end
  end

  describe '#recalculate_remaining_purchased_minutes!' do
    subject { quota.recalculate_remaining_purchased_minutes! }

    where(:purchased_minutes, :namespace_monthly_quota, :previous_amount_used, :expected_purchased_limit) do
      200 | 400 | 0   | 200 # no minutes used
      200 | 0   | 0   | 200 # monthly limit disabled
      0   | 0   | 0   | 0   # monthly limit disabled and no purchased minutes
      200 | 400 | nil | 200 # no previous month usage
      200 | 400 | 300 | 200 # previous usage < monthly limit
      200 | 400 | 500 | 100 # previous usage > monthly limit => purchased minutes reduced
      0   | 400 | 500 | 0   # no purchased minutes = nothing reduced
      200 | 400 | 600 | 0   # previous usage == total limit => purchased minutes reduced
      200 | 400 | 800 | 0   # previous usage > total limit => purchased minutes reduced but not negative
    end

    with_them do
      before do
        if previous_amount_used
          create(:ci_namespace_monthly_usage,
            namespace: namespace,
            date: Ci::Minutes::NamespaceMonthlyUsage.beginning_of_month(2.months.ago),
            amount_used: previous_amount_used)

          create(:ci_namespace_monthly_usage,
            namespace: namespace,
            date: Ci::Minutes::NamespaceMonthlyUsage.beginning_of_month(3.months.ago),
            amount_used: 5_000)
        end
      end

      it 'has the expected purchased minutes' do
        subject
        expect(namespace.extra_shared_runners_minutes_limit).to eq(expected_purchased_limit)
      end
    end

    context 'when there are more than 1 shards' do
      where(:purchased_minutes, :namespace_monthly_quota, :previous_amount_used, :expected_purchased_limit) do
        200 | 400 | 0   | 200 # no minutes used
        200 | 0   | 0   | 200 # monthly limit disabled
        0   | 0   | 0   | 0   # monthly limit disabled and no purchased minutes
        200 | 400 | nil | 200 # no previous month usage
        200 | 400 | 300 | 200 # previous usage < monthly limit
        200 | 400 | 500 | 100 # previous usage > monthly limit => purchased minutes reduced
        0   | 400 | 500 | 0   # no purchased minutes = nothing reduced
        200 | 400 | 600 | 0   # previous usage == total limit => purchased minutes reduced
        200 | 400 | 800 | 0   # previous usage > total limit => purchased minutes reduced but not negative
      end

      with_them do
        before do
          if previous_amount_used
            2.times do |index|
              create(:ci_namespace_monthly_usage,
                namespace: namespace,
                date: Ci::Minutes::NamespaceMonthlyUsage.beginning_of_month(2.months.ago),
                amount_used: previous_amount_used / 2.to_f,
                shard_number: index + 1)
            end

            create(:ci_namespace_monthly_usage,
              namespace: namespace,
              date: Ci::Minutes::NamespaceMonthlyUsage.beginning_of_month(3.months.ago),
              amount_used: 5_000)
          end
        end

        it 'has the expected purchased minutes' do
          subject
          expect(namespace.extra_shared_runners_minutes_limit).to eq(expected_purchased_limit)
        end
      end
    end
  end

  context 'when the namespace is in a billed Organization', :saas do
    let_it_be(:billed_organization) { create(:organization) }
    let_it_be_with_refind(:nominated_group) do
      create(:group, organization: billed_organization,
        shared_runners_minutes_limit: 1_000, extra_shared_runners_minutes_limit: 300)
    end

    let_it_be_with_refind(:other_group) do
      create(:group, organization: billed_organization,
        shared_runners_minutes_limit: 500, extra_shared_runners_minutes_limit: 200)
    end

    before_all do
      create(:organization_gitlab_subscription, organization: billed_organization,
        gitlab_subscription: create(:gitlab_subscription, namespace: nominated_group))
    end

    context 'when organization_billing is enabled for the Organization' do
      before do
        stub_feature_flags(organization_billing: billed_organization)
      end

      it 'reads the limits from the nominated group' do
        other_group_quota = described_class.new(other_group)

        expect(other_group_quota.monthly).to eq(1_000)
        expect(other_group_quota.purchased).to eq(300)
      end

      # 1_200 used exceeds the monthly limit under either group's limits, so any recalculation would change the column.
      it 'does not recalculate purchased minutes for another group' do
        create(:ci_namespace_monthly_usage,
          namespace: other_group,
          date: Ci::Minutes::NamespaceMonthlyUsage.beginning_of_month(2.months.ago),
          amount_used: 1_200)

        expect { described_class.new(other_group).recalculate_remaining_purchased_minutes! }
          .not_to change { other_group.reload.extra_shared_runners_minutes_limit }.from(200)
      end

      it 'recalculates purchased minutes for the nominated group' do
        create(:ci_namespace_monthly_usage,
          namespace: nominated_group,
          date: Ci::Minutes::NamespaceMonthlyUsage.beginning_of_month(2.months.ago),
          amount_used: 1_200)

        described_class.new(nominated_group).recalculate_remaining_purchased_minutes!

        expect(nominated_group.reload.extra_shared_runners_minutes_limit).to eq(100)
      end
    end

    context 'when organization_billing is disabled' do
      before do
        stub_feature_flags(organization_billing: false)
      end

      it 'reads the limits from the namespace itself' do
        other_group_quota = described_class.new(other_group)

        expect(other_group_quota.monthly).to eq(500)
        expect(other_group_quota.purchased).to eq(200)
      end
    end
  end
end
