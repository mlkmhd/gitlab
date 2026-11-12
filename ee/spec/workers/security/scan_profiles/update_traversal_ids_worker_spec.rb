# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Security::ScanProfiles::UpdateTraversalIdsWorker, feature_category: :security_testing_configuration do
  let_it_be(:project_ids) { [1, 2, 3] }

  it_behaves_like 'an idempotent worker' do
    let(:job_args) { [project_ids] }
  end

  describe '#perform' do
    it 'delegates to the service' do
      expect(Security::ScanProfiles::UpdateTraversalIdsService).to receive(:execute).with(project_ids)

      described_class.new.perform(project_ids)
    end
  end
end
