# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Ml::ScheduleExperimentDeletionCronWorker, feature_category: :mlops do
  let(:worker) { described_class.new }

  describe '#perform' do
    subject(:perform) { worker.perform }

    context 'when an experiment is ready for deletion' do
      before do
        create(:ml_experiments, deleted_on: 1.minute.ago)
      end

      it 'starts the deletion workers' do
        expect(Ml::DestroyExperimentWorker).to receive(:perform_with_capacity)

        perform
      end

      it_behaves_like 'an idempotent worker'
    end

    context 'when no experiment is ready for deletion' do
      before do
        create(:ml_experiments)
        create(:ml_experiments, deleted_on: 5.minutes.from_now)
      end

      it 'does not start the deletion workers' do
        expect(Ml::DestroyExperimentWorker).not_to receive(:perform_with_capacity)

        perform
      end
    end
  end
end
