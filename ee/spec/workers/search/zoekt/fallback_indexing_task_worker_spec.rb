# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Search::Zoekt::FallbackIndexingTaskWorker, feature_category: :global_search do
  it_behaves_like 'worker with data consistency', described_class, data_consistency: :delayed

  it_behaves_like 'a Zoekt worker deferring on autovacuum of', [:zoekt_repositories, :zoekt_tasks]

  it 'does not defer on the WriteAheadLog indicator' do
    indicators = described_class.database_health_check_attrs[:indicators]

    expect(indicators).to contain_exactly(
      Gitlab::Database::HealthStatus::Indicators::AutovacuumActiveOnTable,
      Gitlab::Database::HealthStatus::Indicators::PatroniApdex,
      Gitlab::Database::HealthStatus::Indicators::WalRate
    )
  end

  describe '#perform', :zoekt_settings_enabled do
    subject(:perform_worker) { described_class.new.perform(*job_args) }

    let_it_be(:project) { create(:project) }
    let_it_be(:job_args) { [project.id] }

    context 'when zoekt is not available' do
      before do
        allow(Search::Zoekt).to receive(:licensed_and_indexing_enabled?).and_return(false)
      end

      it_behaves_like 'an idempotent worker' do
        it 'does not call the IndexingTaskService service' do
          expect(Search::Zoekt::IndexingTaskService).not_to receive(:execute)
          perform_worker
        end
      end
    end

    context 'when zoekt is available' do
      before do
        allow(Search::Zoekt).to receive(:licensed_and_indexing_enabled?).and_return(true)
      end

      it_behaves_like 'an idempotent worker' do
        it 'calls the IndexingTaskService service with the index_repo task type' do
          expect(Search::Zoekt::IndexingTaskService).to receive(:execute).with(project.id, :index_repo)
          perform_worker
        end
      end
    end
  end
end
