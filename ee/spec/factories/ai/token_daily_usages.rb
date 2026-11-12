# frozen_string_literal: true

FactoryBot.define do
  factory :ai_token_daily_usage, class: '::Ai::TokenDailyUsage' do
    organization { association(:common_organization) }
    user
    usage_date { Time.current.utc.to_date }
    add_attribute(:feature) { :chat }
    model { 'claude-sonnet-4-6' }
  end
end
