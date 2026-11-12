# frozen_string_literal: true

FactoryBot.define do
  factory :gitlab_subscription_user_add_on_assignment, class: 'GitlabSubscriptions::UserAddOnAssignment' do
    user
    add_on_purchase { association(:gitlab_subscription_add_on_purchase) }
    organization { add_on_purchase&.organization || association(:common_organization) }
  end
end
