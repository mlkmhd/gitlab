# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Ai::DumpTokenDailyUsageWriteBufferCronWorker, :clean_gitlab_redis_shared_state,
  feature_category: :ai_abstraction_layer do
  let(:payload) { { status: :processed, inserted_rows: 2, dropped_rows: 1 } }

  it_behaves_like 'an idempotent worker'
  it_behaves_like 'worker with data consistency', described_class, data_consistency: :always

  it 'logs the result of draining the buffer' do
    allow_next_instance_of(Ai::TokenDailyUsages::DrainBufferService) do |service|
      allow(service).to receive(:execute).and_return(ServiceResponse.success(payload: payload))
    end

    expect_next_instance_of(described_class) do |worker|
      expect(worker).to receive(:log_extra_metadata_on_done).with(:result, payload)
    end

    described_class.new.perform
  end
end
