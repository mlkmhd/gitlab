# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Security::ProjectTrackedContexts::ReindexVulnerabilitiesOnDefaultBranchChangeWorker, :elastic,
  feature_category: :vulnerability_management do
  let_it_be(:project) { create(:project) }
  let_it_be(:vulnerability_read) { create(:vulnerability_read, project: project) }

  let(:data) { { container_id: project.id, container_type: ::Project.name } }
  let(:event) { ::Repositories::DefaultBranchChangedEvent.new(data: data) }
  let(:elasticsearch_enabled) { true }

  before do
    stub_ee_application_setting(elasticsearch_indexing: elasticsearch_enabled)
  end

  it_behaves_like 'subscribes to event'

  it 'tracks vulnerability reads for re-indexing' do
    expect(::Elastic::ProcessBookkeepingService).to receive(:track!).with(vulnerability_read)

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

    let_it_be(:project_without_reads) { create(:project) }

    it { is_expected.to be(true) }

    context 'when the project has no vulnerability reads' do
      let(:data) { { container_id: project_without_reads.id, container_type: ::Project.name } }

      it { is_expected.to be(false) }
    end

    context 'when skip_default_branch_reindex_without_records is disabled' do
      let(:data) { { container_id: project_without_reads.id, container_type: ::Project.name } }

      before do
        stub_feature_flags(skip_default_branch_reindex_without_records: false)
      end

      it 'returns true without querying vulnerability reads' do
        expect(::Vulnerabilities::Read).not_to receive(:by_projects)

        expect(dispatch).to be(true)
      end
    end
  end

  context 'when elasticsearch is not available' do
    let(:elasticsearch_enabled) { false }

    it_behaves_like 'ignores the published event'
  end

  context 'when is_default migration has not completed' do
    before do
      set_elasticsearch_migration_to(:add_is_default_to_vulnerability, including: false)
    end

    it_behaves_like 'ignores the published event'
  end

  context 'when container type is not Project' do
    let(:data) { { container_id: project.id, container_type: ::GroupWiki.name } }

    it_behaves_like 'ignores the published event'
  end
end
