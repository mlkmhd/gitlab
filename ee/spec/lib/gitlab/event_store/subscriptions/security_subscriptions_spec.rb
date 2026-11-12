# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Gitlab::EventStore::Subscriptions::SecuritySubscriptions, feature_category: :vulnerability_management do
  let(:store) do
    Gitlab::EventStore::Store.new do |store|
      described_class.new(store).register
    end
  end

  context 'for Repositories::DefaultBranchChangedEvent' do
    subject(:publish) do
      data = { container_id: project.id, container_type: ::Project.name }

      store.publish(::Repositories::DefaultBranchChangedEvent.new(data: data))
    end

    let_it_be(:project_with_reads) { create(:project) }
    let_it_be(:project_with_refs) { create(:project) }
    let_it_be(:project_without_rows) { create(:project) }

    let(:vulnerabilities_worker) do
      Security::ProjectTrackedContexts::ReindexVulnerabilitiesOnDefaultBranchChangeWorker
    end

    let(:sbom_worker) { Security::ProjectTrackedContexts::ReindexSbomOccurrencesOnDefaultBranchChangeWorker }

    before_all do
      create(:vulnerability_read, project: project_with_reads)
      create(:sbom_occurrence_ref, project: project_with_refs)
    end

    before do
      stub_ee_application_setting(elasticsearch_indexing: true)
      allow(::Elastic::DataMigrationService).to receive(:migration_has_finished?).and_return(true)
    end

    context 'when the project has vulnerability reads' do
      let(:project) { project_with_reads }

      it 'queues only the vulnerabilities worker' do
        expect(vulnerabilities_worker).to receive(:perform_async)
        expect(sbom_worker).not_to receive(:perform_async)
        expect(sbom_worker).not_to receive(:perform_in)

        publish
      end
    end

    context 'when the project has sbom occurrence refs' do
      let(:project) { project_with_refs }

      it 'queues only the sbom worker' do
        expect(vulnerabilities_worker).not_to receive(:perform_async)
        expect(vulnerabilities_worker).not_to receive(:perform_in)
        expect(sbom_worker).to receive(:perform_async)

        publish
      end
    end

    context 'when the project has no rows to reindex' do
      let(:project) { project_without_rows }

      it 'queues neither worker' do
        expect(vulnerabilities_worker).not_to receive(:perform_async)
        expect(vulnerabilities_worker).not_to receive(:perform_in)
        expect(sbom_worker).not_to receive(:perform_async)
        expect(sbom_worker).not_to receive(:perform_in)

        publish
      end

      context 'when skip_default_branch_reindex_without_records is disabled' do
        before do
          stub_feature_flags(skip_default_branch_reindex_without_records: false)
        end

        it 'queues both workers' do
          expect(vulnerabilities_worker).to receive(:perform_async)
          expect(sbom_worker).to receive(:perform_async)

          publish
        end
      end
    end
  end
end
