# frozen_string_literal: true

require 'spec_helper'

RSpec.describe MergeTrains::RefreshWorker, feature_category: :merge_trains do
  let(:worker) { described_class.new }

  it 'has the `until_executed` deduplicate strategy' do
    expect(described_class.get_deduplicate_strategy).to eq(:until_executed)
  end

  it 'has an option to reschedule once if deduplicated' do
    expect(described_class.get_deduplication_options).to include({ if_deduplicated: :reschedule_once })
  end

  it_behaves_like 'a worker with a concurrency limit scope',
    type: :root_namespace, max_percentage: 0.4, feature_flag: :ci_pipeline_execution_concurrency_limit_scope_wave_one

  describe '#perform' do
    subject { worker.perform(target_project_id, target_branch) }

    let(:project) { create(:project) }
    let(:target_project_id) { project.id }
    let(:target_branch) { 'master' }

    include_examples 'an idempotent worker' do
      let(:job_args) { [target_project_id, target_branch] }
    end

    it 'logs the refresh outcome' do
      allow_next_instance_of(MergeTrains::RefreshService) do |service|
        allow(service).to receive(:execute)
          .and_return(ServiceResponse.success(payload: { cars_processed: 3, deferred: true }))
      end

      expect(worker).to receive(:log_hash_metadata_on_done).with({ cars_processed: 3, deferred: true })

      worker.perform(target_project_id, target_branch)
    end
  end
end
