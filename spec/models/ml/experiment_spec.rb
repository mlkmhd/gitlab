# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Ml::Experiment, feature_category: :mlops do
  let_it_be(:exp) { create(:ml_experiments) }
  let_it_be(:exp2) { create(:ml_experiments, project: exp.project) }
  let_it_be(:model) { create(:ml_models, project: exp.project) }
  let_it_be(:model_experiment) { model.default_experiment }

  let(:iid) { exp.iid }
  let(:exp_name) { exp.name }

  describe 'associations' do
    it { is_expected.to belong_to(:project) }
    it { is_expected.to belong_to(:user) }
    it { is_expected.to have_many(:candidates) }
    it { is_expected.to have_many(:metadata) }
    it { is_expected.to belong_to(:model).class_name('Ml::Model') }
  end

  describe '#destroy' do
    it 'allow experiment without model to be destroyed' do
      experiment = create(:ml_experiments, project: exp.project)

      expect { experiment.destroy! }.to change { Ml::Experiment.count }.by(-1)
    end

    it 'throws error when destroying experiment with model' do
      experiment = create(:ml_models, project: exp.project).default_experiment

      expect { experiment.destroy! }.to raise_error(ActiveRecord::ActiveRecordError)
      expect(experiment.errors.full_messages).to include('Cannot delete an experiment associated to a model')
    end
  end

  describe '#mark_for_deletion' do
    it 'hides the experiment and frees its name', :freeze_time do
      experiment = create(:ml_experiments, project: exp.project)
      name = experiment.name

      expect(experiment.mark_for_deletion).to be(true)

      expect(experiment.reload)
        .to have_attributes(deleted_on: Time.current, name: /\Adeletion_scheduled-#{experiment.id}-\h{16}\z/)
      expect(described_class.by_project_id_and_name(exp.project_id, name)).to be_nil
      expect(build(:ml_experiments, project: exp.project, name: name)).to be_valid
    end

    it 'does not mark an experiment that belongs to a model' do
      experiment = create(:ml_models, project: exp.project).default_experiment

      expect(experiment.mark_for_deletion).to be(false)

      expect(experiment.errors.full_messages).to eq(['Cannot delete an experiment associated to a model'])
      expect(experiment.reload.deleted_on).to be_nil
    end
  end

  describe '.package_name' do
    it { expect(exp.package_name).to eq("ml_experiment_#{exp.iid}") }

    context 'when model belongs to package' do
      it 'is the model name' do
        expect(model_experiment.package_name).to eq(model.name)
      end
    end
  end

  describe '.for_model?' do
    it 'is false if it is not the default experiment for a model' do
      expect(exp.for_model?).to be(false)
    end

    it 'is true if it is not the default experiment for a model' do
      expect(model_experiment.for_model?).to be(true)
    end
  end

  describe '#more_candidates_than?' do
    let_it_be(:experiment) { create(:ml_experiments, project: exp.project) }

    before_all do
      create_list(:ml_candidates, 2, experiment: experiment, project: experiment.project)
      create(:ml_candidates, experiment: exp, project: exp.project)
    end

    it 'counts only the candidates of the experiment', :aggregate_failures do
      expect(experiment.more_candidates_than?(1)).to be(true)
      expect(experiment.more_candidates_than?(2)).to be(false)
    end
  end

  describe '.by_project' do
    subject { described_class.by_project(exp.project) }

    it { is_expected.to match_array([exp, exp2, model_experiment]) }
  end

  describe '.including_project' do
    subject { described_class.including_project }

    it 'loads latest version' do
      expect(subject.first.association_cached?(:project)).to be(true)
    end
  end

  describe '.including_user' do
    subject { described_class.including_user }

    it 'loads latest version' do
      expect(subject.first.association_cached?(:user)).to be(true)
    end
  end

  describe '.including_metadata' do
    subject { described_class.including_metadata }

    it 'loads metadata' do
      expect(subject.first.association_cached?(:metadata)).to be(true)
    end
  end

  describe '.not_deleted' do
    let_it_be(:deleted_exp) { create(:ml_experiments, project: exp.project, deleted_on: Time.current) }

    subject { described_class.by_project(exp.project).not_deleted }

    it { is_expected.to match_array([exp, exp2, model_experiment]) }
  end

  describe '#by_project_id_and_iid' do
    subject { described_class.by_project_id_and_iid(exp.project_id, iid) }

    context 'if exists' do
      it { is_expected.to eq(exp) }
    end

    context 'if does not exist' do
      let(:iid) { non_existing_record_id }

      it { is_expected.to be_nil }
    end

    context 'if marked for deletion' do
      let(:iid) { create(:ml_experiments, project: exp.project, deleted_on: Time.current).iid }

      it { is_expected.to be_nil }
    end
  end

  describe '#by_project_id_and_name' do
    subject { described_class.by_project_id_and_name(exp.project_id, exp_name) }

    context 'if exists' do
      it { is_expected.to eq(exp) }
    end

    context 'if does not exist' do
      let(:exp_name) { 'hello' }

      it { is_expected.to be_nil }
    end

    context 'if marked for deletion' do
      let(:exp_name) { create(:ml_experiments, project: exp.project, deleted_on: Time.current).name }

      it { is_expected.to be_nil }
    end
  end

  describe '.find_or_create' do
    let(:name) { exp.name }
    let(:project) { exp.project }

    subject(:find_or_create) { described_class.find_or_create(project, name, exp.user) }

    context 'when experiments exists' do
      it 'fetches existing experiment', :aggregate_failures do
        expect { find_or_create }.not_to change { Ml::Experiment.count }

        expect(find_or_create).to eq(exp)
      end
    end

    context 'when experiments does not exist' do
      let(:name) { 'a new experiment' }

      it 'creates the experiment', :aggregate_failures do
        expect { find_or_create }.to change { Ml::Experiment.count }.by(1)

        expect(find_or_create.name).to eq(name)
        expect(find_or_create.user).to eq(exp.user)
        expect(find_or_create.project).to eq(project)
      end
    end

    context 'when experiment name exists but project is different' do
      let(:project) { create(:project) }

      it 'creates a model', :aggregate_failures do
        expect { find_or_create }.to change { Ml::Experiment.count }.by(1)

        expect(find_or_create.name).to eq(name)
        expect(find_or_create.user).to eq(exp.user)
        expect(find_or_create.project).to eq(project)
      end
    end
  end

  describe '#with_candidate_count' do
    let_it_be(:exp3) do
      create(:ml_experiments, project: exp.project).tap do |e|
        create_list(:ml_candidates, 3, experiment: e, user: nil)
        create(:ml_candidates, experiment: exp2, user: nil)
      end
    end

    subject { described_class.with_candidate_count.to_h { |e| [e.id, e.candidate_count] } }

    it 'fetches the candidate count', :aggregate_failures do
      expect(subject[exp.id]).to eq(0)
      expect(subject[exp2.id]).to eq(1)
      expect(subject[exp3.id]).to eq(3)
    end
  end

  describe '#package_for_experiment?' do
    using RSpec::Parameterized::TableSyntax

    subject { described_class.package_for_experiment?(package_name) }

    where(:package_name, :id) do
      'ml_experiment_1234' | true
      'ml_experiment_1234abc' | false
      'ml_experiment_abc' | false
      'ml_experiment_' | false
      'blah' | false
    end

    with_them do
      it { is_expected.to be(id) }
    end
  end

  describe "#exclude_experiments_for_models" do
    subject { described_class.by_project(exp.project).exclude_experiments_for_models }

    it 'excludes experiments that belongs to a model' do
      is_expected.to match_array([exp, exp2])
    end
  end

  describe '.ready_for_deletion' do
    let_it_be(:marked) { create(:ml_experiments, project: exp.project, deleted_on: 1.minute.ago) }
    let_it_be(:held) { create(:ml_experiments, project: exp.project, deleted_on: 1.minute.from_now) }

    subject { described_class.by_project(exp.project).ready_for_deletion }

    it 'returns marked experiments, but not unmarked ones or ones that a worker holds' do
      is_expected.to contain_exactly(marked)
    end
  end

  describe '.next_ready_for_deletion' do
    subject { described_class.next_ready_for_deletion }

    it 'returns the experiment marked first, even when it has a higher id' do
      create(:ml_experiments, project: exp.project, deleted_on: 1.hour.ago)
      marked_first = create(:ml_experiments, project: exp.project, deleted_on: 2.hours.ago)

      is_expected.to eq(marked_first)
    end

    it 'returns the lowest id among experiments marked at the same time', :freeze_time do
      lower_id = create(:ml_experiments, project: exp.project, deleted_on: 1.hour.ago)
      create(:ml_experiments, project: exp.project, deleted_on: 1.hour.ago)

      is_expected.to eq(lower_id)
    end

    it 'returns nil when no experiment is ready' do
      create(:ml_experiments, project: exp.project, deleted_on: 1.minute.from_now)

      is_expected.to be_nil
    end
  end
end
