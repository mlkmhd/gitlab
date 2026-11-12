# frozen_string_literal: true

FactoryBot.define do
  factory :application_setting do
    default_projects_limit { 42 }
    import_sources { [] }
    restricted_visibility_levels { [] }
    default_branch_protection_defaults { ::Gitlab::Access::BranchProtection.protection_none }

    after(:build) do |settings|
      ApplicationSettingFipsHelper.ensure_key_restrictions!(settings)
    end
  end
end
