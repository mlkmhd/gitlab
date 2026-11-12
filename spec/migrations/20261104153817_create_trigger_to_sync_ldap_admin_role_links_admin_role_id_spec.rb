# frozen_string_literal: true

require 'spec_helper'
require_migration!

RSpec.describe CreateTriggerToSyncLdapAdminRoleLinksAdminRoleId,
  migration: :gitlab_main_org,
  feature_category: :permissions do
  let(:organizations) { table(:organizations) }
  let(:member_roles) { table(:member_roles) }
  let(:admin_roles) { table(:admin_roles) }
  let(:ldap_admin_role_links) { table(:ldap_admin_role_links) }

  let(:organization) { organizations.create!(name: 'org', path: 'org') }

  # The member_roles trigger is already in place, so these roles get an admin_roles copy.
  let(:role) { create_admin_member_role('Admin reader') }
  let(:other_role) { create_admin_member_role('Admin auditor') }

  def create_admin_member_role(name)
    member_roles.create!(name: name, permissions: { read_admin_users: true }, organization_id: organization.id)
  end

  def create_link(member_role_id)
    ldap_admin_role_links.create!(member_role_id: member_role_id, provider: 'ldapmain', cn: 'admins',
      organization_id: organization.id)
  end

  before do
    migrate!
  end

  it 'copies member_role_id on insert' do
    link = create_link(role.id)

    expect(link.reload.admin_role_id).to eq(role.id)
  end

  it 'copies member_role_id when the link changes role' do
    link = create_link(role.id)

    link.update!(member_role_id: other_role.id)

    expect(link.reload.admin_role_id).to eq(other_role.id)
  end

  it 'keeps admin_role_id when other columns change' do
    link = create_link(role.id)

    link.update!(sync_error: 'failed')

    expect(link.reload.admin_role_id).to eq(role.id)
  end

  context 'when the role has no admin_roles copy yet' do
    before do
      admin_roles.where(id: other_role.id).delete_all
    end

    it 'leaves admin_role_id empty on insert' do
      link = create_link(other_role.id)

      expect(link.reload.admin_role_id).to be_nil
    end

    it 'clears admin_role_id when the link moves to that role' do
      link = create_link(role.id)

      link.update!(member_role_id: other_role.id)

      expect(link.reload.admin_role_id).to be_nil
    end
  end
end
