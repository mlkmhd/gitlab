# frozen_string_literal: true

require 'spec_helper'
require_migration!

RSpec.describe UseMemberRolesIdSeqForAdminRoles, migration: :gitlab_main_org, feature_category: :permissions do
  let(:organizations) { table(:organizations) }
  let(:member_roles) { table(:member_roles) }
  let(:admin_roles) { table(:admin_roles) }

  let(:organization) { organizations.create!(name: 'org', path: 'org') }

  def id_default
    ApplicationRecord.connection.select_value(<<~SQL)
      SELECT pg_get_expr(adbin, adrelid) FROM pg_attrdef
      WHERE adrelid = 'admin_roles'::regclass
        AND adnum = (SELECT attnum FROM pg_attribute WHERE attrelid = 'admin_roles'::regclass AND attname = 'id')
    SQL
  end

  it 'draws admin_roles ids from member_roles_id_seq' do
    reversible_migration do |migration|
      migration.before -> { expect(id_default).to eq("nextval('admin_roles_id_seq'::regclass)") }
      migration.after -> { expect(id_default).to eq("nextval('member_roles_id_seq'::regclass)") }
    end
  end

  it 'gives a new admin role an id that member_roles has not used' do
    migrate!

    # The member_roles trigger copies this role into admin_roles with the same id.
    copied = member_roles.create!(name: 'Admin reader', permissions: { read_admin_users: true },
      organization_id: organization.id)
    created = admin_roles.create!(name: 'Admin auditor', permissions: {}, organization_id: organization.id)

    expect(created.id).to be > copied.id
  end
end
