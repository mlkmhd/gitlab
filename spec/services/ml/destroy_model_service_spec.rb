# frozen_string_literal: true

require 'spec_helper'

RSpec.describe ::Ml::DestroyModelService, feature_category: :mlops do
  let_it_be(:user) { create(:user) }
  let_it_be_with_refind(:model0) { create(:ml_models, :with_latest_version_and_package) }
  let_it_be_with_refind(:model1) { create(:ml_models, :with_latest_version_and_package) }

  let(:model) { model0 }
  let(:service) { described_class.new(model, user) }
  let(:audit_event) do
    {
      name: 'ml_model_destroyed',
      author: user,
      scope: model.project,
      message: "MlModel #{model.name} destroyed",
      target: model
    }
  end

  before do
    allow(Gitlab::Audit::Auditor).to receive(:audit).and_call_original
  end

  describe '#execute', :aggregate_failures do
    subject(:service_result) { service.execute }

    context 'when model fails to delete' do
      before do
        model.project.add_maintainer(user)
      end

      it 'rolls back the transaction and keeps the default experiment visible' do
        experiment_id = model.default_experiment.id
        versioned_candidate = model.versions.first.candidate

        expect(model).to receive(:destroy).and_return(false)

        expect(service_result).to be_error
        expect(Gitlab::Audit::Auditor).not_to have_received(:audit)
        expect(Ml::Experiment.find(experiment_id)).to have_attributes(deleted_on: nil, model_id: model.id)
        expect(versioned_candidate.reload.model_version_id).to eq(model.versions.first.id)
      end

      it 'keeps the default experiment on the returned model' do
        expect(model).to receive(:destroy).and_return(false)

        expect(service_result.payload[:model].default_experiment).to be_present
      end
    end

    context 'when a model exists' do
      before do
        allow_next_instance_of(Packages::MarkPackagesForDestructionService) do |instance|
          allow(instance).to receive(:execute).and_return ServiceResponse.success(message: "")
        end
      end

      it 'destroys the model and its versions and hides its experiment' do
        experiment = model.default_experiment
        versioned_candidate = model.versions.first.candidate

        expect(Ml::DestroyExperimentWorker).not_to receive(:perform_async)

        expect { service_result }.to change { Ml::Model.count }.by(-1).and change { Ml::ModelVersion.count }.by(-1)
        expect(service_result).to be_success
        expect(Gitlab::Audit::Auditor).to have_received(:audit).with(audit_event)
        expect(experiment.reload).to have_attributes(model_id: nil, deleted_on: be_present)
        expect(versioned_candidate.reload.model_version_id).to be_nil
      end

      it 'deletes the experiment and its candidates in the worker' do
        experiment = model.default_experiment
        candidate_ids = experiment.candidates.pluck(:id)

        expect(service_result).to be_success

        Ml::DestroyExperimentWorker.new.perform_work

        expect(Ml::Experiment.find_by(id: experiment.id)).to be_nil
        expect(Ml::Candidate.where(id: candidate_ids)).to be_empty
      end

      context 'when the new name of the experiment is taken' do
        before do
          allow(SecureRandom).to receive(:hex).and_call_original
          allow(SecureRandom).to receive(:hex).with(8).and_return('0123456789abcdef')
          create(:ml_experiments, project: model.project,
            name: "deletion_scheduled-#{model.default_experiment.id}-0123456789abcdef")
        end

        it 'returns the error before marking the packages for destruction' do
          experiment_id = model.default_experiment.id

          expect(Packages::MarkPackagesForDestructionService).not_to receive(:new)

          expect { service_result }.not_to change { Ml::Model.count }
          expect(service_result).to be_error
          expect(service_result.message).to eq(['Name should be unique in the project'])
          expect(Ml::Experiment.find(experiment_id).deleted_on).to be_nil
        end
      end

      context 'when the model has more versions than one batch' do
        let(:model) { create(:ml_models, :with_versions) }

        before do
          stub_const("#{described_class}::VERSIONS_BATCH_SIZE", 1)
        end

        it 'unlinks the candidates of every version' do
          candidates = model.versions.map(&:candidate)

          expect(service_result).to be_success
          expect(Ml::Candidate.where(id: candidates).pluck(:model_version_id)).to eq([nil, nil])
        end

        it 'locks each batch of versions before it unlinks their candidates' do
          log = ActiveRecord::QueryRecorder.new { service_result }.log
          version_locks = log.each_index.select { |i| log[i].match?(/FROM "ml_model_versions".*FOR UPDATE/) }
          unlinks = log.each_index.select { |i| log[i].start_with?('UPDATE "ml_candidates"') }

          expect(version_locks.size).to eq(2)
          expect(unlinks.size).to eq(2)
          expect(version_locks.zip(unlinks)).to all(satisfy { |lock, unlink| lock < unlink })
        end
      end

      context 'when a package cannot be marked for destruction' do
        let(:model) { model1 }

        before do
          allow_next_instance_of(Packages::MarkPackagesForDestructionService) do |instance|
            allow(instance).to receive(:execute).and_return ServiceResponse.error(message: "An error")
          end
        end

        it 'returns success with warning' do
          expect { service_result }.not_to change { Ml::Model.count }
          expect(service_result).to be_error
          expect(service_result.message).to eq("An error")
          expect(Gitlab::Audit::Auditor).not_to have_received(:audit)
        end
      end
    end

    context 'when the packages of the model versions have no files' do
      let(:model) { create(:ml_models, :with_latest_version_and_package) }
      let(:user) { model.project.owner }
      let!(:package) { model.latest_version.package }

      it 'destroys the packages after the audit event' do
        expect(Gitlab::Audit::Auditor).to receive(:audit).with(audit_event).ordered.and_call_original
        expect(Packages::MlModel::DestroyOrphanedPackagesService).to receive(:new).ordered.and_call_original

        expect { service_result }.to change { Packages::Package.count }.by(-1)
        expect(Packages::Package.find_by(id: package.id)).to be_nil
      end

      context 'when an earlier model with the same name left an orphaned package' do
        let!(:earlier_package) do
          create(:ml_model_package, :pending_destruction, project: model.project, name: model.name)
        end

        it 'destroys only the packages of this model' do
          expect { service_result }.to change { Packages::Package.count }.by(-1)
          expect(earlier_package.reload).to be_pending_destruction
        end
      end
    end

    context 'when ml_delete_experiments_in_batches is disabled' do
      before do
        stub_feature_flags(ml_delete_experiments_in_batches: false)
      end

      context 'when model fails to delete' do
        before do
          model.project.add_maintainer(user)
        end

        it 'returns an error without loading the experiment' do
          expect(model).to receive(:destroy).and_return(false)
          expect(model).not_to receive(:default_experiment)

          expect(service_result).to be_error
          expect(Gitlab::Audit::Auditor).not_to have_received(:audit)
        end
      end

      context 'when a model exists' do
        it 'destroys the model and its experiment in the request' do
          allow_next_instance_of(Packages::MarkPackagesForDestructionService) do |instance|
            allow(instance).to receive(:execute).and_return ServiceResponse.success(message: "")
          end
          experiment = model.default_experiment

          expect(Ml::DestroyExperimentWorker).not_to receive(:perform_async)

          expect { service_result }.to change { Ml::Model.count }.by(-1).and change { Ml::ModelVersion.count }.by(-1)
          expect(service_result).to be_success
          expect(Gitlab::Audit::Auditor).to have_received(:audit).with(audit_event)
          expect(Ml::Experiment.find_by(id: experiment.id)).to be_nil
        end
      end
    end
  end
end
