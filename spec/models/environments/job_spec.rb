# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Environments::Job, feature_category: :environment_management do
  it { is_expected.to belong_to(:environment) }
  it { is_expected.to belong_to(:project) }
  it { is_expected.to belong_to(:pipeline).with_foreign_key(:ci_pipeline_id) }
  it { is_expected.to belong_to(:job).with_foreign_key(:ci_job_id) }
  it { is_expected.to belong_to(:deployment).optional }

  describe 'validations' do
    let_it_be(:job_environment, freeze: false) { create(:job_environment) }

    subject { job_environment }

    it { is_expected.to validate_presence_of(:environment_id) }
    it { is_expected.to validate_presence_of(:project_id) }
    it { is_expected.to validate_presence_of(:ci_pipeline_id) }
    it { is_expected.to validate_presence_of(:ci_job_id) }
    it { is_expected.to validate_uniqueness_of(:ci_job_id).scoped_to(:environment_id) }

    it { is_expected.to validate_presence_of(:expanded_environment_name) }
    it { is_expected.to validate_length_of(:expanded_environment_name).is_at_most(255) }
    it { is_expected.to allow_value('valid-environment-name').for(:expanded_environment_name) }
    it { is_expected.not_to allow_value('/invalid/environment/name').for(:expanded_environment_name) }
  end

  describe '.delete_batch_for_environment' do
    let_it_be(:environment) { create(:environment) }
    let_it_be(:job_environments) { create_list(:job_environment, 3, environment: environment) }
    let_it_be(:other_job_environment) { create(:job_environment) }

    it "deletes up to the batch size of the environment's rows and returns how many it deleted", :aggregate_failures do
      expect(described_class.delete_batch_for_environment(environment, 2)).to eq(2)
      expect(described_class.where(environment: environment).count).to eq(1)
      expect(described_class.delete_batch_for_environment(environment, 2)).to eq(1)

      expect(described_class.where(environment: environment)).to be_empty
      expect(described_class.exists?(other_job_environment.id)).to be(true)
    end
  end

  describe '.exists_for?' do
    let_it_be(:environment) { create(:environment) }
    let_it_be(:other_job_environment) { create(:job_environment) }

    it 'returns whether the environment has rows' do
      expect { create(:job_environment, environment: environment) }
        .to change { described_class.exists_for?(environment) }.from(false).to(true)
    end
  end

  describe '#pipeline' do
    it_behaves_like 'a partition-pruned pipeline association' do
      # .reload resets the :pipeline association preloaded by the factory's default block
      let(:related_resource) { create(:job_environment, pipeline: pipeline).reload }
    end
  end
end
