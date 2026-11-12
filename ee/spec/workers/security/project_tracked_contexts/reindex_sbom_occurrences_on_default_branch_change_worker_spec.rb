# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Security::ProjectTrackedContexts::ReindexSbomOccurrencesOnDefaultBranchChangeWorker, :elastic,
  feature_category: :dependency_management do
  let_it_be(:project) { create(:project) }
  let_it_be(:occurrence_ref) { create(:sbom_occurrence_ref, project: project) }

  let(:data) { { container_id: project.id, container_type: ::Project.name } }
  let(:event) { ::Repositories::DefaultBranchChangedEvent.new(data: data) }
  let(:elasticsearch_enabled) { true }

  before do
    stub_ee_application_setting(elasticsearch_indexing: elasticsearch_enabled)
  end

  it_behaves_like 'subscribes to event'

  it 'tracks sbom occurrence refs for re-indexing' do
    expect(::Elastic::ProcessBookkeepingService).to receive(:track!).with(occurrence_ref)

    consume_event(subscriber: described_class, event: event)
  end

  context 'when the project does not exist' do
    let(:data) { { container_id: non_existing_record_id, container_type: ::Project.name } }

    it 'does not track anything' do
      expect(::Elastic::ProcessBookkeepingService).not_to receive(:track!)

      consume_event(subscriber: described_class, event: event)
    end
  end

  describe '.dispatch?' do
    subject(:dispatch) { described_class.dispatch?(event) }

    let_it_be(:project_without_refs) { create(:project) }

    it { is_expected.to be(true) }

    context 'when the project has no sbom occurrence refs' do
      let(:data) { { container_id: project_without_refs.id, container_type: ::Project.name } }

      it { is_expected.to be(false) }
    end

    context 'when skip_default_branch_reindex_without_records is disabled' do
      let(:data) { { container_id: project_without_refs.id, container_type: ::Project.name } }

      before do
        stub_feature_flags(skip_default_branch_reindex_without_records: false)
      end

      it 'returns true without querying sbom occurrence refs' do
        expect(::Sbom::OccurrenceRef).not_to receive(:by_project)

        expect(dispatch).to be(true)
      end
    end
  end

  context 'when elasticsearch is not available' do
    let(:elasticsearch_enabled) { false }

    it_behaves_like 'ignores the published event'
  end

  context 'when create_sbom_occurrence_refs_index migration has not completed' do
    before do
      set_elasticsearch_migration_to(:create_sbom_occurrence_refs_index, including: false)
    end

    it_behaves_like 'ignores the published event'
  end

  context 'when container type is not Project' do
    let(:data) { { container_id: project.id, container_type: ::GroupWiki.name } }

    it_behaves_like 'ignores the published event'
  end
end
