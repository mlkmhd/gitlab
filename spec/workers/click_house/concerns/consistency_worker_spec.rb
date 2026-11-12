# frozen_string_literal: true

require 'spec_helper'

RSpec.describe ClickHouse::Concerns::ConsistencyWorker, feature_category: :value_stream_management do
  let(:worker_class) do
    stub_const('TestConsistencyWorker', Class.new do
      # ApplicationWorker derives the queue from the name when it is included.
      def self.name
        'TestConsistencyWorker'
      end

      include ApplicationWorker
      include ClickHouse::Concerns::ConsistencyWorker

      attr_reader :lease_present_during

      public :strict_caps?

      def init_context
        @context = { last_processed_id: 0 }
        @lease_present_during = {}
      end

      def collect_values(_values)
        lease_present_during[:collect_values] = lease_present?
      end

      def process_collected_values
        lease_present_during[:process_collected_values] = lease_present?
      end

      def table
        'events'
      end

      def batch_column
        'id'
      end

      def pluck_column
        'id'
      end

      private

      def lease_present?
        Gitlab::ExclusiveLease.new(self.class.to_s, timeout: 1).exists?
      end
    end)
  end

  let(:worker) { worker_class.new }

  before do
    allow(worker).to receive(:enabled?).and_return(true)
    allow(worker).to receive(:click_house_each_batch).and_yield([1])
    allow(ClickHouse::SyncCursor).to receive(:cursor_for).and_return(0)
    allow(ClickHouse::SyncCursor).to receive(:update_cursor_for)
  end

  it 'enforces strict caps only with the flag on' do
    stub_feature_flags(clickhouse_consistency_workers_strict_caps: false)
    expect(worker.strict_caps?).to be(false)

    stub_feature_flags(clickhouse_consistency_workers_strict_caps: true)
    expect(worker_class.new.strict_caps?).to be(true)
  end

  context 'with strict caps off' do
    before do
      stub_feature_flags(clickhouse_consistency_workers_strict_caps: false)
    end

    it 'holds the lease around the iteration only' do
      worker.perform

      expect(worker.lease_present_during).to eq(collect_values: true, process_collected_values: false)
      expect(ClickHouse::SyncCursor).to have_received(:update_cursor_for).with('events_consistency_check', 0)
    end
  end

  context 'with strict caps on' do
    it 'holds the lease through the processing' do
      worker.perform

      expect(worker.lease_present_during).to eq(collect_values: true, process_collected_values: true)
      expect(ClickHouse::SyncCursor).to have_received(:update_cursor_for).with('events_consistency_check', 0)
    end
  end
end
