# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Ml::DestroyExperimentWorker, :aggregate_failures, feature_category: :mlops do
  let_it_be(:project) { create(:project) }
  let_it_be(:other_candidate) { create(:ml_candidates, :with_metrics_and_params, project: project) }

  let(:experiment) { create(:ml_experiments, project: project, deleted_on: 1.hour.ago) }
  let(:worker) { described_class.new }

  before do
    stub_const("Ml::DeleteExperimentRunsService::BATCH_PAUSE", 0)
  end

  it_behaves_like 'worker with data consistency', described_class, data_consistency: :sticky

  describe '#perform_work' do
    subject(:perform_work) { worker.perform_work }

    let!(:candidates) do
      create_list(:ml_candidates, 3, :with_metrics_and_params, :with_metadata, experiment: experiment, project: project)
    end

    it 'deletes the runs, their metrics, params and metadata, and the experiment' do
      candidate_ids = candidates.map(&:id)

      perform_work

      expect(Ml::Experiment.find_by(id: experiment.id)).to be_nil
      expect(Ml::Candidate.where(id: candidate_ids)).to be_empty
      expect(Ml::CandidateMetric.where(candidate_id: candidate_ids)).to be_empty
      expect(Ml::CandidateParam.where(candidate_id: candidate_ids)).to be_empty
      expect(Ml::CandidateMetadata.where(candidate_id: candidate_ids)).to be_empty
      expect(other_candidate.reload.metrics.count).to eq(2)
      expect(worker.logging_extras).to include(
        'extra.ml_destroy_experiment_worker.experiment_id' => experiment.id,
        'extra.ml_destroy_experiment_worker.project_id' => project.id,
        'extra.ml_destroy_experiment_worker.deleted_rows' => 21,
        'extra.ml_destroy_experiment_worker.completed' => true
      )
    end

    it 'picks the experiment marked first, not the one with the lowest id' do
      marked_earlier = create(:ml_experiments, project: project, deleted_on: 2.hours.ago)

      perform_work

      expect(Ml::Experiment.find_by(id: marked_earlier.id)).to be_nil
      expect(experiment.reload).to be_present
    end

    it 'skips an experiment that another job holds' do
      held = create(:ml_experiments, project: project, deleted_on: 5.minutes.from_now)

      expect { perform_work }.not_to change { held.reload.deleted_on }
      expect(Ml::Experiment.find_by(id: experiment.id)).to be_nil
    end

    it 'picks experiments with FOR UPDATE SKIP LOCKED' do
      recorder = ActiveRecord::QueryRecorder.new { perform_work }

      expect(recorder.log.grep(/FROM "ml_experiments".*FOR UPDATE SKIP LOCKED/).size).to eq(1)
    end

    context 'when the slice reaches the row limit' do
      before do
        stub_const("Ml::DeleteExperimentRunsService::BATCH_SIZE", 1)
        stub_const("#{described_class}::MAX_DELETED_ROWS", 7)
      end

      it 'stops after the batch that reaches the limit and puts the experiment back in the queue', :freeze_time do
        expect { perform_work }.to change { experiment.candidates.count }.from(3).to(2)

        expect(experiment.reload.deleted_on).to eq(Time.current)
        expect(worker.logging_extras).to include('extra.ml_destroy_experiment_worker.completed' => false)
      end

      it 'deletes the experiment over several slices' do
        3.times { described_class.new.perform_work }

        expect(Ml::Experiment.find_by(id: experiment.id)).to be_present

        described_class.new.perform_work

        expect(Ml::Experiment.find_by(id: experiment.id)).to be_nil
      end
    end

    context 'when deleting fails' do
      before do
        allow_next_found_instance_of(Ml::Experiment) do |instance|
          allow(instance).to receive(:destroy!).and_raise(ActiveRecord::StatementInvalid)
        end
      end

      it 'logs the error and keeps the experiment held until the claim expires', :freeze_time do
        expect(Gitlab::ErrorTracking).to receive(:log_exception)
          .with(an_instance_of(ActiveRecord::StatementInvalid),
            hash_including(experiment_id: experiment.id, Labkit::Fields::GL_PROJECT_ID => project.id, deleted_rows: 21))

        perform_work

        expect(experiment.reload.deleted_on).to eq(described_class::CLAIM_TIMEOUT.from_now)
      end
    end

    context 'when claiming an experiment fails' do
      before do
        allow(Ml::Experiment).to receive(:next_ready_for_deletion).and_raise(ActiveRecord::StatementInvalid)
      end

      it 'logs the error without an experiment and deletes nothing', :aggregate_failures do
        expect(Gitlab::ErrorTracking).to receive(:log_exception)
          .with(an_instance_of(ActiveRecord::StatementInvalid),
            hash_including(class: described_class.name, experiment_id: nil))

        expect { perform_work }.not_to raise_error

        expect(Ml::Experiment.ready_for_deletion).to contain_exactly(experiment)
        expect(experiment.candidates.count).to eq(3)
      end
    end

    context 'when no experiment is marked for deletion' do
      let(:experiment) { create(:ml_experiments, project: project) }

      it 'does not delete anything' do
        expect { perform_work }.not_to change { Ml::Candidate.count }
        expect(experiment.reload).to be_present
      end
    end

    it_behaves_like 'an idempotent worker' do
      it 'deletes the experiment and keeps the runs of other experiments' do
        perform_idempotent_work

        expect(Ml::Experiment.find_by(id: experiment.id)).to be_nil
        expect(other_candidate.reload.metrics.count).to eq(2)
      end
    end
  end

  describe '#remaining_work_count' do
    before do
      create(:ml_experiments, project: project, deleted_on: 5.minutes.from_now)
      create(:ml_experiments, project: project)
    end

    it 'counts the experiments that are ready for deletion' do
      experiment

      expect(worker.remaining_work_count).to eq(1)
    end
  end
end
