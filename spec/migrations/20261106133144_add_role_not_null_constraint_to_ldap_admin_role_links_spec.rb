# frozen_string_literal: true

require 'spec_helper'
require_migration!

RSpec.describe AddRoleNotNullConstraintToLdapAdminRoleLinks,
  migration: :gitlab_main_org,
  feature_category: :permissions do
  let(:organizations) { table(:organizations) }
  let(:ldap_admin_role_links) { table(:ldap_admin_role_links) }

  let(:organization) { organizations.create!(name: 'org', path: 'org') }

  it 'rejects a link with no role' do
    migrate!

    expect do
      ldap_admin_role_links.create!(provider: 'ldapmain', cn: 'admins', organization_id: organization.id)
    end.to raise_error(ActiveRecord::StatementInvalid, /check_/)
  end
end
