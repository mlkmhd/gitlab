# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Analytics::LegacyAiUsageDatabaseWriteBuffer, :clean_gitlab_redis_shared_state, feature_category: :value_stream_management do
  subject(:buffer) { described_class.new(buffer_key: 'ai/usage_event') }

  it 'keeps the legacy key prefix' do
    buffer.add({ foo: 'bar' })

    Gitlab::Redis::SharedState.with do |redis|
      expect(redis.llen('usage_event_write_buffer_ai/usage_event')).to eq(1)
    end
  end

  it 'inherits the pending cap and counts the dropped rows under the bare buffer key' do
    dropped = instance_double(Prometheus::Client::Counter, increment: nil)
    stub_const("#{described_class}::MAX_PENDING", 1)
    allow(Gitlab::Metrics).to receive(:counter)
      .with(:gitlab_database_write_buffer_dropped_total, anything).and_return(dropped)

    buffer.add([{ n: 1 }, { n: 2 }])

    expect(buffer.pending).to eq(1)
    expect(dropped).to have_received(:increment).with({ buffer: 'ai/usage_event' }, 1)
  end
end
