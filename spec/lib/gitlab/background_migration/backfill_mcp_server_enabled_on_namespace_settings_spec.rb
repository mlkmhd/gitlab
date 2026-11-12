# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Gitlab::BackgroundMigration::BackfillMcpServerEnabledOnNamespaceSettings, feature_category: :mcp_server do
  let(:organizations) { table(:organizations) }
  let(:namespaces) { table(:namespaces) }
  let(:namespace_settings) { table(:namespace_settings) }

  let!(:organization) { organizations.create!(name: 'Default', path: 'default') }
  let!(:root_group) { create_namespace(mcp_server_enabled: true) }

  describe '#perform' do
    it 'sets NULL to true for subgroups, personal namespaces, and root groups' do
      subgroup = create_namespace(parent_id: root_group.id, mcp_server_enabled: nil)
      user_namespace = create_namespace(type: 'User', mcp_server_enabled: nil)
      blank_root_group = create_namespace(mcp_server_enabled: nil)

      perform_migration

      expect(setting_for(subgroup).mcp_server_enabled).to be true
      expect(setting_for(user_namespace).mcp_server_enabled).to be true
      expect(setting_for(blank_root_group).mcp_server_enabled).to be true
    end

    it 'leaves false values alone' do
      group = create_namespace(mcp_server_enabled: false)

      perform_migration

      expect(setting_for(group).mcp_server_enabled).to be false
    end

    # update_all doesn't set updated_at, but every UPDATE writes a new tuple and so changes ctid.
    it 'does not rewrite rows that already have a value' do
      ctid = -> { namespace_settings.where(namespace_id: root_group.id).pick(Arel.sql('ctid::text')) }

      expect { perform_migration }.not_to change { ctid.call }
    end

    it 'does not update rows outside the cursor range' do
      in_range = create_namespace(mcp_server_enabled: nil)
      out_of_range = create_namespace(mcp_server_enabled: nil)

      perform_migration(end_cursor: [in_range.id])

      expect(setting_for(in_range).mcp_server_enabled).to be true
      expect(setting_for(out_of_range).mcp_server_enabled).to be_nil
    end
  end

  def perform_migration(end_cursor: [namespace_settings.maximum(:namespace_id)])
    described_class.new(
      start_cursor: [namespace_settings.minimum(:namespace_id)],
      end_cursor: end_cursor,
      batch_table: :namespace_settings,
      batch_column: :namespace_id,
      sub_batch_size: 100,
      pause_ms: 0,
      connection: ApplicationRecord.connection
    ).perform
  end

  def setting_for(namespace)
    namespace_settings.find_by(namespace_id: namespace.id)
  end

  def create_namespace(mcp_server_enabled:, parent_id: nil, type: 'Group')
    path = "namespace-#{SecureRandom.hex(4)}"
    namespace = namespaces.create!(name: path, path: path, type: type, parent_id: parent_id,
      organization_id: organization.id)
    namespace_settings.create!(namespace_id: namespace.id, mcp_server_enabled: mcp_server_enabled)
    namespace
  end
end
