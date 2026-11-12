# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Gitlab::Geo::RegistryBlobLocationBackfillCursor, :clean_gitlab_redis_shared_state, feature_category: :geo_replication do
  subject(:cursor) { described_class.new('lfs_object') }

  describe '#claim_range' do
    it 'claims sequential, non-overlapping ranges' do
      expect(cursor.claim_range(1000)).to eq(1..1000)
      expect(cursor.claim_range(1000)).to eq(1001..2000)
    end

    it 'shares the position between instances' do
      cursor.claim_range(10)

      expect(described_class.new('lfs_object').claim_range(10)).to eq(11..20)
    end

    it 'keeps a separate position per replicable' do
      cursor.claim_range(10)

      expect(described_class.new('job_artifact').claim_range(10)).to eq(1..10)
    end
  end

  describe '#position' do
    it 'is zero before any claim and the highest claimed ID after' do
      expect(cursor.position).to eq(0)

      cursor.claim_range(1000)

      expect(cursor.position).to eq(1000)
    end
  end

  describe '#done?' do
    it 'is false until marked done' do
      expect(cursor).not_to be_done
    end

    it 'persists once marked done' do
      cursor.mark_done!

      expect(described_class.new('lfs_object')).to be_done
      expect(described_class.new('job_artifact')).not_to be_done
    end

    it 'has no expiry' do
      cursor.mark_done!

      Gitlab::Redis::SharedState.with do |redis|
        expect(redis.ttl("#{described_class::KEY_PREFIX}:lfs_object:done")).to eq(-1)
      end
    end
  end
end
