# frozen_string_literal: true

require 'spec_helper'

RSpec.describe ClickHouse::WriteBuffer, :clean_gitlab_redis_shared_state, feature_category: :database do
  let(:table_name) { 'test' }

  describe '.add' do
    subject(:add_event) { described_class.add(table_name, event_hash) }

    let(:event_hash) { { foo: 'bar' } }

    it 'saves ClickHouse event to Redis' do
      expect do
        add_event
      end.to change {
        Gitlab::Redis::SharedState.with do |redis|
          redis.lrange(described_class::BUFFER_KEY_PREFIX + table_name, 0, 10)
        end
      }.from([]).to([event_hash.to_json])
    end
  end

  describe 'the pending cap' do
    let(:table_name) { 'ai_usage_events' }
    let(:dropped) { instance_double(Prometheus::Client::Counter, increment: nil) }

    before do
      stub_const("#{described_class}::MAX_PENDING", 2)
      allow(Gitlab::Metrics).to receive(:counter).and_call_original
      allow(Gitlab::Metrics).to receive(:counter)
        .with(:gitlab_clickhouse_write_buffer_dropped_total, anything).and_return(dropped)
    end

    context 'when the table buffer is full' do
      before do
        described_class.add(table_name, { n: 1 })
        described_class.add(table_name, { n: 2 })
      end

      it 'drops the new event and counts it' do
        described_class.add(table_name, { n: 3 })

        expect(described_class.pending(table_name)).to eq(2)
        expect(described_class.pop(table_name, 3)).to eq([{ n: 1 }, { n: 2 }])
        expect(dropped).to have_received(:increment).with({ table: table_name }).once
      end

      it 'keeps a requeued batch' do
        described_class.add_all(table_name, [{ n: 3 }, { n: 4 }])

        expect(described_class.pending(table_name)).to eq(4)
        expect(described_class.pop(table_name, 4)).to eq([{ n: 1 }, { n: 2 }, { n: 3 }, { n: 4 }])
        expect(dropped).not_to have_received(:increment)
      end

      it 'allows an event for another table' do
        described_class.add('other_table', { n: 3 })

        expect(described_class.pending('other_table')).to eq(1)
        expect(dropped).not_to have_received(:increment)
      end
    end

    context 'when the buffer is already past the cap' do
      before do
        stub_feature_flags(analytics_write_buffer_protection: false)
        3.times { |n| described_class.add(table_name, { n: n }) }
        stub_feature_flags(analytics_write_buffer_protection: true)
      end

      it 'drops the new event and keeps the existing ones' do
        described_class.add(table_name, { n: 3 })

        expect(described_class.pending(table_name)).to eq(3)
        expect(described_class.pop(table_name, 4)).to eq([{ n: 0 }, { n: 1 }, { n: 2 }])
        expect(dropped).to have_received(:increment).with({ table: table_name }).once
      end
    end

    context 'when the table is not in CAPPED_TABLES' do
      let(:table_name) { 'ai_audit_events' }

      it 'adds everything past the limit' do
        3.times { |n| described_class.add(table_name, { n: n }) }

        expect(described_class.pending(table_name)).to eq(3)
        expect(dropped).not_to have_received(:increment)
      end
    end

    context 'when the flag is off' do
      before do
        stub_feature_flags(analytics_write_buffer_protection: false)
      end

      it 'adds everything' do
        3.times { |n| described_class.add(table_name, { n: n }) }

        expect(described_class.pending(table_name)).to eq(3)
        expect(dropped).not_to have_received(:increment)
      end
    end
  end

  describe '.pending' do
    subject(:pending_count) { described_class.pending(table_name) }

    it 'returns 0 when the buffer is empty' do
      expect(pending_count).to eq(0)
    end

    it 'returns the number of events added to the buffer' do
      described_class.add(table_name, { foo: 'bar' })
      described_class.add(table_name, { foo: 'baz' })
      described_class.add(table_name, { foo: 'qux' })

      expect(pending_count).to eq(3)
    end

    it 'returns an integer (not nil or string)' do
      expect(pending_count).to be_a(Integer)
    end

    it 'decrements after pop' do
      described_class.add(table_name, { foo: 'bar' })
      described_class.add(table_name, { foo: 'baz' })
      described_class.pop(table_name, 1)

      expect(pending_count).to eq(1)
    end

    it 'does not count entries for other tables' do
      described_class.add('other_table', { foo: 'bar' })

      expect(pending_count).to eq(0)
    end
  end

  describe '.pop_events' do
    let(:limit) { 2 }

    let(:event1) { { foo: 'bar' } }
    let(:event2) { { foo: 'bar2' } }
    let(:event3) { { foo: 'bar3' } }

    before do
      described_class.add(table_name, event1)
      described_class.add(table_name, event2)
      described_class.add(table_name, event3)
    end

    it 'pops events from redis' do
      expect(described_class.pop(table_name, limit)).to eq([event1, event2])
      expect(described_class.pop(table_name, limit)).to eq([event3])
      expect(described_class.pop(table_name, limit)).to eq([])
    end
  end

  describe '.add_all' do
    subject(:add_all) { described_class.add_all(table_name, event_hashes) }

    let(:event_hashes) { [{ foo: 'bar' }, { foo: 'baz' }] }

    it 'appends the events to the buffer in the given order' do
      described_class.add(table_name, { foo: 'first' })

      add_all

      expect(described_class.pop(table_name, 10)).to eq([{ foo: 'first' }, { foo: 'bar' }, { foo: 'baz' }])
    end

    context 'when the list is empty' do
      let(:event_hashes) { [] }

      it 'does not touch Redis' do
        expect(Gitlab::Redis::SharedState).not_to receive(:with)

        add_all
      end
    end
  end

  it_behaves_like 'using redis backwards compatible methods' do
    let(:buffer_key) { 'clickhouse_write_buffer_test_model' }
  end
end
