# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Gitlab::BackgroundMigration::BackfillSecNamespaceMirrors, feature_category: :organization do
  let(:organizations) { table(:organizations, database: :main, primary_key: :id) }
  let(:namespaces) { table(:namespaces, database: :main, primary_key: :id) }
  let(:sec_namespace_mirrors) { table(:sec_namespace_mirrors, database: :sec, primary_key: :namespace_id) }

  let!(:organization) { organizations.create!(name: 'organization', path: 'organization') }
  let!(:other_organization) { organizations.create!(name: 'other', path: 'other') }

  let!(:group) do
    namespaces.create!(name: 'group', path: 'group', organization_id: organization.id).tap do |namespace|
      namespace.update!(traversal_ids: [namespace.id])
    end
  end

  let!(:subgroup) do
    namespaces.create!(
      name: 'subgroup', path: 'subgroup', organization_id: organization.id, parent_id: group.id
    ).tap do |namespace|
      namespace.update!(traversal_ids: [group.id, namespace.id])
    end
  end

  def perform_migration(sub_batch_size: 1)
    described_class.new(
      start_cursor: [namespaces.minimum(:id)],
      end_cursor: [namespaces.maximum(:id)],
      batch_table: :namespaces,
      batch_column: :id,
      sub_batch_size: sub_batch_size,
      pause_ms: 0,
      connection: ApplicationRecord.connection
    ).perform
  end

  describe '#perform' do
    it 'mirrors namespaces that have no mirror yet' do
      expect { perform_migration }.to change { sec_namespace_mirrors.count }.from(0).to(2)

      expect(sec_namespace_mirrors.find(subgroup.id)).to have_attributes(
        organization_id: organization.id,
        traversal_ids: [group.id, subgroup.id]
      )
    end

    it 'refreshes mirrors that drifted from the namespace' do
      sec_namespace_mirrors.create!(
        namespace_id: subgroup.id,
        organization_id: other_organization.id,
        traversal_ids: [subgroup.id]
      )

      perform_migration

      expect(sec_namespace_mirrors.find(subgroup.id)).to have_attributes(
        organization_id: organization.id,
        traversal_ids: [group.id, subgroup.id]
      )
    end

    it 'writes one upsert per sub-batch rather than one per row' do
      3.times do |i|
        namespaces.create!(name: "extra#{i}", path: "extra#{i}", organization_id: organization.id)
      end

      recorder = ActiveRecord::QueryRecorder.new { perform_migration(sub_batch_size: 2) }

      # 5 namespaces in sub-batches of 2 is 3 sub-batches, so a per-row upsert would log 5.
      expect(namespaces.count).to eq(5)
      expect(recorder.log.grep(/INSERT INTO "sec_namespace_mirrors"/).count).to eq(3)
    end
  end
end
