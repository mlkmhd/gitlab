# frozen_string_literal: true

require 'spec_helper'

RSpec.describe ::Ml::DestroyExperimentService, feature_category: :mlops do
  let_it_be(:project) { create(:project) }
  let_it_be(:model) { create(:ml_models, project: project) }

  let(:experiment) { create(:ml_experiments, :with_candidates, project: project) }
  let(:experiment_with_model) { create(:ml_experiments, project: project, model_id: model.id) }
  let(:service) { described_class.new(experiment) }

  describe '#execute' do
    subject(:destroy_result) { service.execute }

    it 'hides the experiment without enqueuing a job', :aggregate_failures do
      expect(Ml::DestroyExperimentWorker).not_to receive(:perform_async)

      expect(destroy_result).to be_success
      expect(destroy_result.payload[:experiment]).to eq(experiment)
      expect(experiment.reload.deleted_on).to be_present
      expect(Ml::Experiment.by_project_id_and_iid(project.id, experiment.iid)).to be_nil
      expect(experiment.candidates.count).to eq(2)
    end

    it 'deletes the experiment and its candidates in the worker' do
      candidate_ids = experiment.candidates.pluck(:id)

      expect(destroy_result).to be_success

      Ml::DestroyExperimentWorker.new.perform_work

      expect(Ml::Experiment.find_by(id: experiment.id)).to be_nil
      expect(Ml::Candidate.where(id: candidate_ids)).to be_empty
    end

    context 'when experiment fails to be marked for deletion' do
      before do
        allow(experiment).to receive(:save).and_return(false)
      end

      it 'returns an error response' do
        expect(destroy_result).to be_error
      end
    end

    context 'when the new name of the experiment is taken' do
      before do
        allow(SecureRandom).to receive(:hex).and_call_original
        allow(SecureRandom).to receive(:hex).with(8).and_return('0123456789abcdef')
        create(:ml_experiments, project: project, name: "deletion_scheduled-#{experiment.id}-0123456789abcdef")
      end

      it 'returns the error and does not hide the experiment', :aggregate_failures do
        expect(destroy_result).to be_error
        expect(destroy_result.message).to eq(['Name should be unique in the project'])
        expect(experiment.reload.deleted_on).to be_nil
      end
    end

    context 'when experiment is associated with a model' do
      let(:experiment) { experiment_with_model }

      it 'returns an error response and does not hide the experiment', :aggregate_failures do
        expect(Ml::DestroyExperimentWorker).not_to receive(:perform_async)

        expect(destroy_result).to be_error
        expect(destroy_result.message[0]).to eq('Cannot delete an experiment associated to a model')
        expect(experiment.reload.deleted_on).to be_nil
      end
    end

    context 'when ml_delete_experiments_in_batches is disabled' do
      before do
        stub_feature_flags(ml_delete_experiments_in_batches: false)
      end

      context 'when experiment is successfully destroyed' do
        it 'destroys the experiment in the request', :aggregate_failures do
          expect(Ml::DestroyExperimentWorker).not_to receive(:perform_async)

          expect(destroy_result).to be_success
          expect(destroy_result.payload[:experiment]).to eq(experiment)
          expect(Ml::Experiment.find_by(id: experiment.id)).to be_nil
        end
      end

      context 'when experiment fails to destroy' do
        before do
          allow(experiment).to receive(:destroy).and_return(false)
        end

        it 'returns an error response' do
          expect(destroy_result).to be_error
        end
      end

      context 'when experiment is associated with a model' do
        let(:experiment) { experiment_with_model }

        it 'returns an error response and does not destroy the experiment', :aggregate_failures do
          expect(destroy_result).to be_error
          expect(destroy_result.message[0]).to eq('Cannot delete an experiment associated to a model')
          expect(Ml::Experiment.find_by(id: experiment.id)).to eq(experiment)
        end
      end
    end
  end
end
