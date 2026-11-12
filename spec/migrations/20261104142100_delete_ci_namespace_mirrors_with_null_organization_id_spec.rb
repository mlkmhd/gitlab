# frozen_string_literal: true

require 'spec_helper'
require_migration!

RSpec.describe DeleteCiNamespaceMirrorsWithNullOrganizationId, migration: :gitlab_ci,
  feature_category: :continuous_integration do
  let(:mirrors) { table(:ci_namespace_mirrors, database: :ci) }
  let(:connection) { Ci::ApplicationRecord.connection }
  let(:constraint_name) { 'check_f051ac59d0' }

  let!(:mirror_with_organization) do
    mirrors.create!(namespace_id: 1, traversal_ids: [1], organization_id: 1)
  end

  # The NOT VALID constraint added by 20261022150315 rejects new null values.
  # Drop it while seeding the orphans, then re-add it NOT VALID so the migration
  # sees the production-like schema: constraint present, pre-existing null rows.
  let!(:orphaned_mirrors) do
    connection.remove_check_constraint(:ci_namespace_mirrors, name: constraint_name)

    records = (2..4).map do |id|
      mirrors.create!(namespace_id: id, traversal_ids: [id], organization_id: nil)
    end

    connection.add_check_constraint(
      :ci_namespace_mirrors,
      'organization_id IS NOT NULL',
      name: constraint_name,
      validate: false
    )

    records
  end

  # Three orphans against a batch of two: the loop runs twice, the second pass
  # is a partial batch, and a third pass finds nothing and stops.
  before do
    stub_const("#{described_class}::BATCH_SIZE", 2)
  end

  describe '#up' do
    it 'deletes every mirror with a null organization_id and keeps the others', :aggregate_failures do
      migrate!

      expect(mirrors.where(id: orphaned_mirrors.map(&:id))).to be_empty
      expect(mirrors.where(id: mirror_with_organization.id)).to exist
    end

    it 'leaves the constraint ready to be validated' do
      migrate!

      expect { connection.execute("ALTER TABLE ci_namespace_mirrors VALIDATE CONSTRAINT #{constraint_name}") }
        .not_to raise_error
    end
  end

  describe '#down' do
    it 'is a no-op' do
      migrate!

      expect { schema_migrate_down! }.not_to change { mirrors.count }
    end
  end
end
