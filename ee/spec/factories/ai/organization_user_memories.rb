# frozen_string_literal: true

FactoryBot.define do
  factory :organization_ai_user_memory, class: 'Ai::OrganizationUserMemory' do
    user
    organization { association(:common_organization) }
    content { 'I prefer concise responses' }
  end
end
