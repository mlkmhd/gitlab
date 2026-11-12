# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Gitlab::Instrumentation::RequestStoreCounters, :request_store, feature_category: :scalability do
  let(:key) { :request_store_counters_spec_key }
  let(:counters) { Class.new { extend Gitlab::Instrumentation::RequestStoreCounters } }

  describe '.counter_value' do
    it 'returns 0 when the counter was never incremented' do
      expect(counters.counter_value(key)).to eq(0)
    end

    it 'returns the stored value' do
      Gitlab::SafeRequestStore[key] = 5

      expect(counters.counter_value(key)).to eq(5)
    end
  end

  describe '.increment_counter' do
    it 'adds 1 by default' do
      expect { counters.increment_counter(key) }.to change { counters.counter_value(key) }.from(0).to(1)
    end

    it 'adds the given amount to the running total' do
      counters.increment_counter(key, 2)
      counters.increment_counter(key, 0.5)

      expect(counters.counter_value(key)).to eq(2.5)
    end

    it 'stores the counter under the given request-store key' do
      counters.increment_counter(key, 3)

      expect(Gitlab::SafeRequestStore[key]).to eq(3)
    end

    context 'when the request store is not active' do
      before do
        allow(Gitlab::SafeRequestStore).to receive(:active?).and_return(false)
      end

      it 'does not write and leaves the counter at 0' do
        expect(Gitlab::SafeRequestStore).not_to receive(:[]=).with(key, anything)

        counters.increment_counter(key)

        expect(counters.counter_value(key)).to eq(0)
      end
    end
  end

  describe '.counter_duration' do
    it 'rounds the total to the instrumentation precision' do
      counters.increment_counter(key, 0.1234567)

      expect(counters.counter_duration(key)).to eq(0.123457)
    end

    it 'returns 0 when nothing was recorded' do
      expect(counters.counter_duration(key)).to eq(0)
    end
  end
end
