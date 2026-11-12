# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'Groups > Billing > post-trial usage card', :js, :saas,
  :with_namespace_eligible_trials, feature_category: :subscription_management do
  include SubscriptionPortalHelpers

  let_it_be(:user) { create(:user, :with_namespace) }
  let(:current_organization) { user.organization }
  let_it_be(:group) { create(:group, owners: user) }
  let_it_be(:trial_ends_on) { 20.days.ago.to_date }

  before do
    stub_signing_key
    stub_application_setting(check_namespace_plan: true)
    stub_billing_plans(group.id)
    stub_subscription_monthly_commitment_request

    create(
      :gitlab_subscription, :free,
      namespace: group, trial: true,
      trial_starts_on: trial_ends_on - 30.days, trial_ends_on: trial_ends_on
    )
    create(
      :gitlab_subscription_trial_usage,
      namespace: group,
      trial_starts_on: trial_ends_on - 30.days,
      trial_ends_on: trial_ends_on,
      max_seats_used: 6,
      compute_minutes_used: 375,
      compute_minutes_month: trial_ends_on.beginning_of_month,
      credits_used: 40
    )

    sign_in(user)
    visit group_billings_path(group)
  end

  it 'shows the owner what the group used during the trial' do
    within_testid('post-trial-usage-card') do
      expect(page).to have_content('Your GitLab Ultimate trial has ended')
      expect(page).to have_testid('post-trial-usage-metric-seats', text: '6')
      expect(page).to have_testid('post-trial-usage-metric-compute-minutes', text: '375')
      expect(page).to have_testid('post-trial-usage-metric-credits', text: '40')
    end
  end

  it 'tracks the impression with the variant and visible metrics', :capture_snowplow_events do
    expect(page).to have_testid('post-trial-usage-card')

    wait_for_snowplow_event(
      action: 'view_post_trial_usage_card_group_billing',
      label: 'usage',
      property: 'seats,compute-minutes,credits'
    )
  end

  context 'when the owner clicks the upgrade CTA' do
    it 'tracks the click with the variant and visible metrics', :capture_snowplow_events do
      find_by_testid('post-trial-usage-card-cta').click

      expect(page).to have_current_path(%r{/subscriptions/new\?.*gl_namespace_id=#{group.id}}, url: true)

      visit group_billings_path(group)

      wait_for_snowplow_event(
        action: 'click_upgrade_on_post_trial_usage_card_group_billing',
        label: 'usage',
        property: 'seats,compute-minutes,credits'
      )
    end
  end

  context 'when the post_trial_usage_card flag is disabled' do
    before do
      stub_feature_flags(post_trial_usage_card: false)

      visit group_billings_path(group)
    end

    it 'does not show the card' do
      expect(page).to have_testid('free-trial-plan-billing-content')
      expect(page).to have_no_testid('post-trial-usage-card')
    end
  end

  context 'when the owner dismisses the card' do
    it 'tracks the dismissal with the variant and visible metrics', :capture_snowplow_events do
      find_by_testid('post-trial-usage-card-dismiss').click

      expect(page).to have_no_testid('post-trial-usage-card')

      wait_for_snowplow_event(
        action: 'dismiss_post_trial_usage_card_group_billing',
        label: 'usage',
        property: 'seats,compute-minutes,credits'
      )
    end

    it 'keeps it dismissed on the next page load' do
      find_by_testid('post-trial-usage-card-dismiss').click

      expect(page).to have_no_testid('post-trial-usage-card')

      wait_for('callout dismissed') do
        Users::GroupCallout.where(
          user_id: user.id,
          group_id: group.id,
          feature_name: BillingPlansHelper::POST_TRIAL_USAGE_CARD_CALLOUT
        ).exists?
      end

      visit group_billings_path(group)

      expect(page).to have_testid('free-trial-plan-billing-content')
      expect(page).to have_no_testid('post-trial-usage-card')
    end
  end
end
