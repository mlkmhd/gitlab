# frozen_string_literal: true

require 'spec_helper'

using RSpec::Parameterized::TableSyntax

RSpec.describe GitlabSchema.types['GitlabSubscriptionUsageUserUsage'],
  feature_category: :consumables_cost_management do
  it { expect(described_class.graphql_name).to eq('GitlabSubscriptionUsageUserUsage') }
  it { expect(described_class).to require_graphql_authorizations(:read_user) }

  it 'has expected fields' do
    expect(described_class).to have_graphql_fields([
      :credits_used,
      :monthly_waiver_credits_used,
      :overage_credits_used,
      :monthly_commitment_credits_used,
      :paid_tier_trial_credits_used,
      :total_credits,
      :total_credits_used,
      :non_billable_credits_used
    ])
  end

  describe 'deprecated fields' do
    where(:field_name, :reason) do
      'creditsUsed'                  | ref(:wallet_breakdown)
      'monthlyCommitmentCreditsUsed' | ref(:wallet_breakdown)
      'monthlyWaiverCreditsUsed'     | ref(:wallet_breakdown)
      'overageCreditsUsed'           | ref(:wallet_breakdown)
      'paidTierTrialCreditsUsed'     | ref(:wallet_breakdown)
      'totalCredits'                 | ref(:no_replacement)
    end

    with_them do
      let(:no_replacement) do
        'No longer supported. Deprecated in GitLab 19.6.'
      end

      let(:wallet_breakdown) do
        'Usage is reported for the entire subscription, not broken down by wallet. ' \
          'Use `totalCreditsUsed`. Deprecated in GitLab 19.6.'
      end

      it 'is deprecated for removal in 20.0' do
        expect(described_class.fields[field_name].deprecation_reason).to eq(reason)
      end
    end
  end
end
