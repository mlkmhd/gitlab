# frozen_string_literal: true

require 'spec_helper'
require_migration!

RSpec.describe BackfillLdapAdminRoleLinksAdminRoleId,
  migration: :gitlab_main_org,
  feature_category: :permissions do
  let(:organizations) { table(:organizations) }
  let(:member_roles) { table(:member_roles) }
  let(:admin_roles) { table(:admin_roles) }
  let(:ldap_admin_role_links) { table(:ldap_admin_role_links) }

  let(:organization) { organizations.create!(name: 'org', path: 'org') }

  # The member_roles trigger is already in place, so this role gets an admin_roles copy.
  let(:role) do
    member_roles.create!(name: 'Admin reader', permissions: { read_admin_users: true },
      organization_id: organization.id)
  end

  # Inserts a link the way it existed before the sync trigger, with admin_role_id empty.
  def create_link(member_role_id)
    ldap_admin_role_links.create!(member_role_id: member_role_id, provider: 'ldapmain', cn: 'admins',
      organization_id: organization.id).tap do |link|
      link.update_columns(admin_role_id: nil)
    end
  end

  it 'fills admin_role_id from member_role_id' do
    link = create_link(role.id)

    expect { migrate! }.to change { link.reload.admin_role_id }.from(nil).to(role.id)
  end

  it 'skips links whose role has no admin_roles copy' do
    admin_roles.where(id: role.id).delete_all
    link = create_link(role.id)

    expect { migrate! }.not_to change { link.reload.admin_role_id }.from(nil)
  end
end
