# frozen_string_literal: true

require 'spec_helper'

RSpec.describe RedisCacheable::CachedAttributesReader, :clean_gitlab_redis_cache, feature_category: :fleet_visibility do
  # The hash tag puts the keys in one slot, so the MGET examples also work on Redis Cluster.
  let(:key) { 'cache:{cached_attributes_reader_spec}:1:attributes' }
  let(:reader) { described_class.new(key) }

  def write_cache(values, to: nil)
    Gitlab::Redis::Cache.with { |redis| redis.set(to || key, Gitlab::Json.dump(values)) }
  end

  describe '#attributes' do
    subject(:attributes) { reader.attributes }

    context 'when the key exists' do
      before do
        write_cache({ name: 'value' })
      end

      it 'returns the parsed attributes with symbol keys' do
        expect(attributes).to eq(name: 'value')
      end

      it 'reads Redis only once' do
        reader.attributes

        expect(RedisCommands::Recorder.new { reader.attributes }.count).to eq(0)
      end
    end

    context 'when the key does not exist' do
      it { is_expected.to be_nil }

      it 'does not read Redis again' do
        reader.attributes

        expect(RedisCommands::Recorder.new { reader.attributes }.count).to eq(0)
      end
    end
  end

  describe '#key' do
    it 'returns the Redis key' do
      expect(reader.key).to eq(key)
    end
  end

  describe '.preload' do
    let(:other_key) { 'cache:{cached_attributes_reader_spec}:2:attributes' }
    let(:other_reader) { described_class.new(other_key) }
    let(:readers) { [reader, other_reader] }

    shared_examples 'a batched read' do
      it 'fills every reader without another Redis call' do
        write_cache({ name: 'value' })
        write_cache({ name: 'other' }, to: other_key)

        described_class.preload(readers)

        recorder = RedisCommands::Recorder.new do
          expect(reader.attributes).to eq(name: 'value')
          expect(other_reader.attributes).to eq(name: 'other')
        end

        expect(recorder.count).to eq(0)
      end

      it 'stores nil for a missing key without another Redis call' do
        write_cache({ name: 'value' })

        described_class.preload(readers)

        recorder = RedisCommands::Recorder.new do
          expect(other_reader.attributes).to be_nil
        end

        expect(recorder.count).to eq(0)
      end

      it 'skips readers that are already loaded' do
        write_cache({ name: 'value' })
        reader.attributes
        write_cache({ name: 'changed' })

        described_class.preload(readers)

        expect(reader.attributes).to eq(name: 'value')
      end

      it 'reads nothing when all readers are loaded' do
        reader.attributes

        expect(Gitlab::Redis::Cache).not_to receive(:with)

        described_class.preload([reader])
      end
    end

    context 'when Redis is not a cluster' do
      before do
        allow(Gitlab::Redis::ClusterUtil).to receive(:cluster?).and_return(false)
      end

      it_behaves_like 'a batched read'

      it 'reads all keys with one MGET' do
        recorder = RedisCommands::Recorder.new { described_class.preload(readers) }

        expect(recorder.log).to eq([['mget', key, other_key]])
      end
    end

    context 'when Redis is a cluster' do
      before do
        allow(Gitlab::Redis::ClusterUtil).to receive(:cluster?).and_return(true)
      end

      it_behaves_like 'a batched read'

      it 'reads the keys with ClusterUtil.batch_get' do
        expect(Gitlab::Redis::ClusterUtil).to receive(:batch_get)
          .with([key, other_key], anything).and_call_original

        described_class.preload(readers)
      end
    end
  end
end
