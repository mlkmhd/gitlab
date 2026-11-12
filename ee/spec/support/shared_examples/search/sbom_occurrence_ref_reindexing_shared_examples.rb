# frozen_string_literal: true

# Requires `occurrence_ref`, the Sbom::OccurrenceRef whose document the write invalidates, and
# `reindex`, the action under test.
RSpec.shared_examples 'tracks sbom occurrence refs for reindexing' do
  before do
    stub_ee_application_setting(elasticsearch_indexing: true)
    set_elasticsearch_migration_to(:create_sbom_occurrence_refs_index)
  end

  it 'tracks the occurrence refs' do
    expect(::Elastic::ProcessBookkeepingService).to receive(:track!).with(occurrence_ref)

    reindex
  end

  context 'when the create_sbom_occurrence_refs_index migration has not completed' do
    before do
      set_elasticsearch_migration_to(:create_sbom_occurrence_refs_index, including: false)
    end

    it 'does not track the occurrence refs' do
      expect(::Elastic::ProcessBookkeepingService).not_to receive(:track!)

      reindex
    end

    it 'does not query sbom_occurrence_refs' do
      queries = ActiveRecord::QueryRecorder.new { reindex }

      expect(queries.log).not_to include(a_string_matching('sbom_occurrence_refs'))
    end
  end
end
