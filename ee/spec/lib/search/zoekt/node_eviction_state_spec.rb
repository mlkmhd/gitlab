# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Search::Zoekt::NodeEvictionState, :clean_gitlab_redis_shared_state, feature_category: :global_search do
  let_it_be(:node) { create(:zoekt_node) }
  let_it_be(:other_node) { create(:zoekt_node) }

  describe '.record_over_watermark' do
    it 'keeps the time the node was first seen over the watermark' do
      first_seen = freeze_time { described_class.record_over_watermark(node) }

      travel_to(1.hour.from_now) do
        expect(described_class.record_over_watermark(node)).to eq(first_seen)
      end
    end

    it 'expires the time of a node that is no longer checked' do
      described_class.record_over_watermark(node)

      ttl = Gitlab::Redis::SharedState.with do |redis|
        redis.ttl("#{described_class::OVER_WATERMARK_KEY_PREFIX}:#{node.id}")
      end

      expect(ttl).to be_between(1, described_class::OVER_WATERMARK_TTL.to_i)
    end

    it 'tracks each node separately' do
      first_seen = freeze_time { described_class.record_over_watermark(node) }

      travel_to(10.minutes.from_now) do
        expect(described_class.record_over_watermark(other_node)).to be > first_seen
      end
    end
  end

  describe '.clear_over_watermark' do
    it 'starts a new over-watermark period the next time the node is recorded' do
      freeze_time { described_class.record_over_watermark(node) }
      described_class.clear_over_watermark(node)

      travel_to(1.hour.from_now) do
        expect(described_class.record_over_watermark(node)).to eq(Time.current.change(usec: 0))
      end
    end
  end

  describe 'cooldown' do
    it 'lists nodes in cooldown until it is ended' do
      described_class.start_cooldown(node)

      expect(described_class.cooldown_node_ids).to contain_exactly(node.id)

      described_class.end_cooldown(node)

      expect(described_class.cooldown_node_ids).to be_empty
    end

    it 'expires after the cooldown TTL' do
      described_class.start_cooldown(node)

      travel_to((described_class::COOLDOWN_TTL + 1.minute).from_now) do
        expect(described_class.cooldown_node_ids).to be_empty
      end
    end

    it 'clears the over-watermark period of the node' do
      freeze_time { described_class.record_over_watermark(node) }
      described_class.start_cooldown(node)

      travel_to(1.hour.from_now) do
        expect(described_class.record_over_watermark(node)).to eq(Time.current.change(usec: 0))
      end
    end
  end
end
