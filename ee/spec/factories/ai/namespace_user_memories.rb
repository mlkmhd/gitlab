# frozen_string_literal: true

FactoryBot.define do
  factory :namespace_ai_user_memory, class: 'Ai::NamespaceUserMemory' do
    user
    namespace { association(:group) }
    content { 'I prefer concise responses' }
  end
end
