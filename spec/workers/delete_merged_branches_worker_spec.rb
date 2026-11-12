# frozen_string_literal: true

require 'spec_helper'

RSpec.describe DeleteMergedBranchesWorker, feature_category: :source_code_management do
  subject(:worker) { described_class.new }

  let_it_be(:project) { create(:project, :small_repo) }

  it 'caps concurrent jobs to bound the per-branch high-urgency fan-out' do
    expect(described_class.get_concurrency_limit).to eq(20)
  end

  describe "#perform" do
    it_behaves_like 'an idempotent worker' do
      let(:project) { create(:project, :repository) }
      let(:job_args) { [project.id, project.first_owner.id] }

      it 'deletes merged branches and keeps unmerged branches across repeated runs', :aggregate_failures do
        perform_idempotent_work

        expect(project.repository.branch_names).not_to include('improve/awesome')
        expect(project.repository.branch_names).to include('master', 'feature')
      end
    end

    it "delegates to Branches::DeleteMergedService" do
      expect_next_instance_of(::Branches::DeleteMergedService) do |instance|
        expect(instance).to receive(:execute).and_return(true)
      end

      worker.perform(project.id, project.first_owner.id)
    end

    it "returns false when project was not found" do
      expect(worker.perform('unknown', project.first_owner.id)).to be_falsy
    end

    context 'when the user no longer exists' do
      it 'returns without deleting branches or raising an error', :aggregate_failures do
        expect(::Branches::DeleteMergedService).not_to receive(:new)

        expect { worker.perform(project.id, non_existing_record_id) }.not_to raise_error
      end
    end
  end
end
