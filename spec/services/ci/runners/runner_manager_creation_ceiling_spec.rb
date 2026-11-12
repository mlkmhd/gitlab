# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Ci::Runners::RunnerManagerCreationCeiling, :clean_gitlab_redis_shared_state, :freeze_time,
  feature_category: :runner_core do
  let_it_be(:runner) { create(:ci_runner) }
  let_it_be(:other_runner) { create(:ci_runner) }

  describe '.record' do
    it 'adds the reached runners' do
      described_class.record(reached_runner_ids: [runner.id], cleared_runner_ids: [])

      expect(described_class.reached?(runner)).to be(true)
      expect(described_class.reached?(other_runner)).to be(false)
      expect(described_class.runner_ids).to contain_exactly(runner.id)
    end

    it 'removes the cleared runners' do
      described_class.record(reached_runner_ids: [runner.id, other_runner.id], cleared_runner_ids: [])
      described_class.record(reached_runner_ids: [], cleared_runner_ids: [runner.id])

      expect(described_class.reached?(runner)).to be(false)
      expect(described_class.runner_ids).to contain_exactly(other_runner.id)
    end

    it 'renews the entries of runners reached again' do
      described_class.record(reached_runner_ids: [runner.id], cleared_runner_ids: [])

      travel(described_class::TTL - 1.minute)
      described_class.record(reached_runner_ids: [runner.id], cleared_runner_ids: [])
      travel(2.minutes)

      expect(described_class.reached?(runner)).to be(true)
    end

    it 'sets an expiry on the key' do
      described_class.record(reached_runner_ids: [runner.id], cleared_runner_ids: [])

      ttl = Gitlab::Redis::SharedState.with { |redis| redis.ttl(described_class::REDIS_KEY) }

      expect(ttl).to be_within(5).of(described_class::TTL.to_i)
    end
  end

  context 'when an entry is not renewed' do
    before do
      described_class.record(reached_runner_ids: [runner.id], cleared_runner_ids: [])
    end

    it 'expires it after the TTL' do
      travel(described_class::TTL + 1.second)

      expect(described_class.reached?(runner)).to be(false)
      expect(described_class.runner_ids).to be_empty
    end
  end

  describe '.runner_ids' do
    it 'returns at most MAX_RUNNERS runners' do
      stub_const("#{described_class}::MAX_RUNNERS", 1)
      described_class.record(reached_runner_ids: [runner.id, other_runner.id], cleared_runner_ids: [])

      expect(described_class.runner_ids.size).to eq(1)
    end
  end

  context 'when Redis is unavailable' do
    before do
      allow(Gitlab::Redis::SharedState).to receive(:with).and_raise(::Redis::CannotConnectError)
      allow(Gitlab::ErrorTracking).to receive(:track_and_raise_for_dev_exception)
    end

    it 'allows creation and tracks the error' do
      expect(described_class.reached?(runner)).to be(false)
      expect(Gitlab::ErrorTracking).to have_received(:track_and_raise_for_dev_exception)
        .with(an_instance_of(::Redis::CannotConnectError))
    end

    it 'returns no runners and tracks the error' do
      expect(described_class.runner_ids).to eq([])
      expect(Gitlab::ErrorTracking).to have_received(:track_and_raise_for_dev_exception)
        .with(an_instance_of(::Redis::CannotConnectError))
    end

    it 'skips recording and tracks the error' do
      expect { described_class.record(reached_runner_ids: [runner.id], cleared_runner_ids: []) }.not_to raise_error
      expect(Gitlab::ErrorTracking).to have_received(:track_and_raise_for_dev_exception)
        .with(an_instance_of(::Redis::CannotConnectError))
    end
  end
end
