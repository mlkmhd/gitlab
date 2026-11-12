# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Analytics::DatabaseWriteBuffer, feature_category: :devops_reports do
  let(:model_name) { 'test_model' }

  subject(:buffer) { described_class.new(buffer_key: model_name) }

  describe '#add', :clean_gitlab_redis_shared_state do
    it 'adds given attributes json to test_model_db_write_buffer redis list' do
      buffer.add({ foo: 'bar' })

      Gitlab::Redis::SharedState.with do |redis|
        expect(redis.lindex('test_model_db_write_buffer', 0)).to eq({ foo: 'bar' }.to_json)
      end
    end

    it 'adds multiple attributes json to test_model_db_write_buffer redis list' do
      buffer.add([{ foo: 'bar' }, { foo: 'baz' }])

      Gitlab::Redis::SharedState.with do |redis|
        expect(redis.lindex('test_model_db_write_buffer', 0)).to eq({ foo: 'bar' }.to_json)
        expect(redis.lindex('test_model_db_write_buffer', 1)).to eq({ foo: 'baz' }.to_json)
      end
    end
  end

  describe 'the pending cap', :clean_gitlab_redis_shared_state do
    let(:dropped) { instance_double(Prometheus::Client::Counter, increment: nil) }

    before do
      stub_const("#{described_class}::MAX_PENDING", 3)
      allow(Gitlab::Metrics).to receive(:counter).and_call_original
      allow(Gitlab::Metrics).to receive(:counter)
        .with(:gitlab_database_write_buffer_dropped_total, anything).and_return(dropped)
    end

    it 'drops the rows past the cap and counts them' do
      buffer.add([{ n: 1 }, { n: 2 }])
      buffer.add([{ n: 3 }, { n: 4 }, { n: 5 }])

      expect(buffer.pending).to eq(3)
      expect(buffer.pop(3).pluck('n')).to eq([1, 2, 3])
      expect(dropped).to have_received(:increment).with({ buffer: model_name }, 2)
    end

    it 'drops a single row once the buffer is full' do
      buffer.add([{ n: 1 }, { n: 2 }, { n: 3 }])
      buffer.add({ n: 4 })

      expect(buffer.pending).to eq(3)
      expect(dropped).to have_received(:increment).with({ buffer: model_name }, 1)
    end

    it 'does not apply to a requeued batch' do
      buffer.add([{ n: 1 }, { n: 2 }, { n: 3 }])
      buffer.requeue([{ n: 4 }, { n: 5 }])

      expect(buffer.pending).to eq(5)
      expect(buffer.pop(5).pluck('n')).to eq([1, 2, 3, 4, 5])
      expect(dropped).not_to have_received(:increment)
    end

    context 'when the buffer is already past the cap' do
      before do
        stub_feature_flags(analytics_write_buffer_protection: false)
        buffer.add([{ n: 1 }, { n: 2 }, { n: 3 }, { n: 4 }])
        stub_feature_flags(analytics_write_buffer_protection: true)
      end

      it 'drops every new row and keeps the existing ones' do
        buffer.add([{ n: 5 }, { n: 6 }])

        expect(buffer.pending).to eq(4)
        expect(buffer.pop(4).pluck('n')).to eq([1, 2, 3, 4])
        expect(dropped).to have_received(:increment).with({ buffer: model_name }, 2)
      end
    end

    context 'when the flag is off' do
      before do
        stub_feature_flags(analytics_write_buffer_protection: false)
      end

      it 'adds everything' do
        buffer.add([{ n: 1 }, { n: 2 }, { n: 3 }, { n: 4 }])

        expect(buffer.pending).to eq(4)
        expect(dropped).not_to have_received(:increment)
      end
    end
  end

  describe '#pending', :clean_gitlab_redis_shared_state do
    it 'returns the number of buffered hashes' do
      expect(buffer.pending).to eq(0)

      buffer.add([{ foo: 'bar' }, { foo: 'baz' }])

      expect(buffer.pending).to eq(2)
    end
  end

  describe '#pop', :clean_gitlab_redis_shared_state do
    it 'pops limited array of elements from test_model_db_write_buffer key' do
      buffer.add({ foo: 'bar' })
      buffer.add({ foo: 'baz' })
      buffer.add({ foo: 'bad' })

      Gitlab::Redis::SharedState.with do |redis|
        expect(redis.llen('test_model_db_write_buffer')).to eq(3)
      end
      expect(buffer.pop(2)).to eq([{ 'foo' => 'bar' }, { 'foo' => 'baz' }])
      Gitlab::Redis::SharedState.with do |redis|
        expect(redis.llen('test_model_db_write_buffer')).to eq(1)
      end
      expect(buffer.pop(2)).to eq([{ 'foo' => 'bad' }])
      Gitlab::Redis::SharedState.with do |redis|
        expect(redis.llen('test_model_db_write_buffer')).to eq(0)
      end
    end
  end
end
