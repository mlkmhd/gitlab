# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Security::AnalyzersStatus::UpdateArchivedAnalyzerStatusWorker, feature_category: :security_asset_inventories do
  let_it_be(:projects) { create_list(:project, 2) }

  let(:project_ids) { projects.map(&:id) }

  subject(:run_worker) { described_class.new.perform(project_ids) }

  describe '#perform' do
    before do
      allow(Security::AnalyzersStatus::UpdateArchivedService).to receive(:execute)
    end

    it 'calls the UpdateArchivedService with the projects' do
      run_worker

      expect(Security::AnalyzersStatus::UpdateArchivedService)
        .to have_received(:execute).with(match_array(projects)).once
    end

    it 'accepts a single project id from a previously queued job' do
      described_class.new.perform(projects.first.id)

      expect(Security::AnalyzersStatus::UpdateArchivedService)
        .to have_received(:execute).with(match_array([projects.first]))
    end

    it 'calls the service once per batch' do
      stub_const("#{described_class}::BATCH_SIZE", 1)

      run_worker

      expect(Security::AnalyzersStatus::UpdateArchivedService).to have_received(:execute).twice
    end
  end

  include_examples 'an idempotent worker' do
    let_it_be(:project) { create(:project) }

    let(:job_args) { [[project.id]] }
  end
end
