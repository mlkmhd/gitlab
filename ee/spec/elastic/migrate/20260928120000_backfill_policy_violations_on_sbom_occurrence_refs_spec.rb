# frozen_string_literal: true

require 'spec_helper'
require File.expand_path('ee/elastic/migrate/20260928120000_backfill_policy_violations_on_sbom_occurrence_refs.rb')

RSpec.describe BackfillPolicyViolationsOnSbomOccurrenceRefs, :elastic, feature_category: :dependency_management do
  let(:version) { 20260928120000 }

  include_examples 'migration reindexes all data' do
    let(:objects) { create_list(:sbom_occurrence_ref, 3) }
    let(:factory_to_create_objects) { :sbom_occurrence_ref }
    let(:expected_throttle_delay) { 15.seconds }
    let(:expected_batch_size) { 10_000 }
  end

  describe '#referenceable_documents' do
    let(:migration) { described_class.new(version) }
    let_it_be(:occurrence_ref) { create(:sbom_occurrence_ref) }
    let_it_be(:orphaned_ref) do
      create(:sbom_occurrence_ref).tap { |ref| ref.update_column(:project_id, non_existing_record_id) }
    end

    # A deleted project leaves its rows behind until loose foreign key cleanup runs, and
    # Sbom::OccurrenceRef#es_parent raises on them inside track!.
    it 'drops records whose project is gone' do
      expect(migration.referenceable_documents([occurrence_ref, orphaned_ref])).to contain_exactly(occurrence_ref)
    end

    it 'logs how many were skipped' do
      expect(migration).to receive(:log).with('Skipped occurrence refs with no project', count: 1,
        project_ids: [non_existing_record_id])

      migration.referenceable_documents([occurrence_ref, orphaned_ref])
    end

    it 'does not log when every record is referenceable' do
      expect(migration).not_to receive(:log)

      expect(migration.referenceable_documents([occurrence_ref])).to contain_exactly(occurrence_ref)
    end
  end

  describe '#migrate with an orphaned ref' do
    let(:migration) { described_class.new(version) }

    let_it_be(:occurrence_ref) { create(:sbom_occurrence_ref) }
    let_it_be(:orphaned_ref) do
      create(:sbom_occurrence_ref).tap { |ref| ref.update_column(:project_id, non_existing_record_id) }
    end

    # migrate persists current_id to the migrations index, which outlives the example.
    before do
      migration.set_migration_state(current_id: 0)
    end

    it 'does not raise and advances the cursor past the orphan' do
      expect { migration.migrate }.not_to raise_error

      expect(migration.migration_state[:current_id]).to eq(Sbom::OccurrenceRef.maximum(:id))
    end

    it 'still tracks the referenceable refs sharing the batch' do
      tracked_refs = []
      allow(::Elastic::ProcessInitialBookkeepingService).to receive(:track!) { |*refs| tracked_refs.concat(refs) }

      migration.migrate

      expect(tracked_refs).to include(occurrence_ref)
      expect(tracked_refs).not_to include(orphaned_ref)
    end
  end
end
