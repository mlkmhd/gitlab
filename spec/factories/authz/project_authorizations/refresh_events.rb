# frozen_string_literal: true

FactoryBot.define do
  factory :authz_refresh_event, class: 'Authz::ProjectAuthorizations::RefreshEvent' do
    target_type { :project }
    sequence(:target_id)
  end
end
