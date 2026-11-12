# frozen_string_literal: true

require 'spec_helper'
require_migration!

RSpec.describe DropNotNullFromLdapAdminRoleLinksMemberRoleId,
  migration: :gitlab_main_org,
  feature_category: :permissions do
  let(:organizations) { table(:organizations) }
  let(:admin_roles) { table(:admin_roles) }
  let(:ldap_admin_role_links) { table(:ldap_admin_role_links) }

  let(:organization) { organizations.create!(name: 'org', path: 'org') }

  def member_role_id_nullable?
    ldap_admin_role_links.reset_column_information
    ldap_admin_role_links.columns_hash['member_role_id'].null
  end

  it 'allows a NULL member_role_id' do
    reversible_migration do |migration|
      migration.before -> { expect(member_role_id_nullable?).to be(false) }
      migration.after -> { expect(member_role_id_nullable?).to be(true) }
    end
  end

  it 'keeps the admin_role_id set on a link without member_role_id' do
    migrate!

    admin_role = admin_roles.create!(name: 'Admin reader', permissions: {}, organization_id: organization.id)
    link = ldap_admin_role_links.create!(admin_role_id: admin_role.id, provider: 'ldapmain', cn: 'admins',
      organization_id: organization.id)

    expect(link.reload.admin_role_id).to eq(admin_role.id)
  end
end
