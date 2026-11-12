# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Ai::TokenDailyUsages::DrainBufferService, :clean_gitlab_redis_shared_state,
  feature_category: :ai_abstraction_layer do
  let_it_be(:organization) { create(:organization) }
  let_it_be(:user) { create(:user) }
  let_it_be(:group) { create(:group, organization: organization) }

  let(:timestamp) { Time.current.utc.beginning_of_day + 12.hours }

  def execute
    described_class.new.execute
  end

  def add_to_buffer(at: timestamp, **overrides)
    Ai::TokenDailyUsage.write_buffer.add({
      organization_id: organization.id,
      traversal_ids: group.traversal_ids,
      user_id: user.id,
      feature: 'chat',
      model: 'claude-sonnet-4-5',
      usage_date: at.utc.to_date,
      input_tokens: 100,
      output_tokens: 20,
      events_count: 1,
      namespace_id: group.id,
      event: 'report_duo_chat_token_usage',
      timestamp: at
    }.merge(overrides))
  end

  it 'writes nothing when the buffer is empty' do
    result = execute

    expect(result).to be_success
    expect(result.payload).to eq({ status: :processed, inserted_rows: 0, dropped_rows: 0 })
    expect(Ai::TokenDailyUsage.count).to eq(0)
  end

  it 'adds across batches of one run' do
    stub_const('Ai::TokenDailyUsages::FlushBufferService::BATCH_SIZE', 1)
    add_to_buffer
    add_to_buffer(at: timestamp + 1.minute)

    expect(execute.payload).to eq({ status: :processed, inserted_rows: 2, dropped_rows: 0 })
    expect(Ai::TokenDailyUsage.all).to contain_exactly(
      have_attributes(input_tokens: 200, output_tokens: 40, events_count: 2)
    )
  end

  it 'adds the rows the model rejects across batches of one run' do
    stub_const('Ai::TokenDailyUsages::FlushBufferService::BATCH_SIZE', 2)
    add_to_buffer
    add_to_buffer(model: 'claude-haiku-4-5', input_tokens: -1)
    add_to_buffer(at: timestamp + 1.minute)
    add_to_buffer(at: timestamp + 1.minute, model: 'claude-haiku-4-5', input_tokens: -1)

    expect(execute.payload).to eq({ status: :processed, inserted_rows: 2, dropped_rows: 2 })
    expect(Ai::TokenDailyUsage.count).to eq(1)
  end

  it 'keeps draining after a batch whose rows the model rejects' do
    stub_const('Ai::TokenDailyUsages::FlushBufferService::BATCH_SIZE', 1)
    add_to_buffer(input_tokens: -1)
    add_to_buffer(at: timestamp + 1.minute)

    expect(execute.payload).to eq({ status: :processed, inserted_rows: 1, dropped_rows: 1 })
    expect(Ai::TokenDailyUsage.count).to eq(1)
  end

  it 'stops after the batch that runs past the time limit' do
    stub_const('Ai::TokenDailyUsages::FlushBufferService::BATCH_SIZE', 1)
    add_to_buffer
    add_to_buffer(at: timestamp + 1.minute)
    allow_next_instance_of(Gitlab::Metrics::RuntimeLimiter) do |limiter|
      allow(limiter).to receive(:over_time?).and_return(true)
    end

    expect(execute.payload).to eq({ status: :over_time, inserted_rows: 1, dropped_rows: 0 })
    expect(Ai::TokenDailyUsage.count).to eq(1)
  end

  it 'runs for the maximum runtime' do
    expect(Gitlab::Metrics::RuntimeLimiter).to receive(:new).with(200.seconds).and_call_original

    execute
  end
end
