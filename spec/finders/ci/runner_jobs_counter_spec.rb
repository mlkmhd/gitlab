# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Ci::RunnerJobsCounter, '#call', feature_category: :fleet_visibility do
  let_it_be(:project) { create(:project) }
  let_it_be(:runner) { create(:ci_runner, :instance) }
  let_it_be(:other_runner) { create(:ci_runner, :instance) }

  let_it_be(:older_pipeline) { create(:ci_pipeline, project: project, partition_id: 100) }
  let_it_be(:newer_pipeline) { create(:ci_pipeline, project: project, partition_id: ci_testing_partition_id) }

  let(:limit) { 10 }
  # Page 2 has an offset, which the count must not keep
  let(:jobs) { runner.builds.page(2).per(1) }

  subject(:count) { described_class.new(limit: limit).call(jobs) }

  before_all do
    create_list(:ci_build, 2, pipeline: older_pipeline, runner: runner)
    create(:ci_build, pipeline: newer_pipeline, runner: runner)
    create(:ci_build, pipeline: newer_pipeline, runner: other_runner)
  end

  context 'with ci_partitions rows' do
    before_all do
      create(:ci_partition, :active, id: 100)
      create(:ci_partition, :current, id: ci_testing_partition_id)
    end

    it 'counts the jobs in every partition' do
      expect(count).to eq(3)
    end

    context 'when the jobs exceed the limit' do
      let(:limit) { 1 }

      it 'returns one more than the limit' do
        expect(count).to eq(2)
      end
    end

    context 'with jobs filtered to the user projects and a status' do
      let_it_be(:user) { create(:user, reporter_of: project) }
      let_it_be(:other_project_pipeline) do
        create(:ci_pipeline, project: create(:project), partition_id: ci_testing_partition_id)
      end

      let(:jobs) { Ci::RunnerJobsFinder.new(runner, user, status: 'success').execute.page(2).per(1) }

      before_all do
        create(:ci_build, :success, pipeline: older_pipeline, runner: runner)
        create(:ci_build, :success, pipeline: newer_pipeline, runner: runner)
        create(:ci_build, :success, pipeline: other_project_pipeline, runner: runner)
      end

      it 'counts only the matching jobs in every partition' do
        expect(count).to eq(2)
      end
    end
  end

  context 'without ci_partitions rows' do
    it 'counts the jobs in every partition' do
      expect(count).to eq(3)
    end
  end
end
