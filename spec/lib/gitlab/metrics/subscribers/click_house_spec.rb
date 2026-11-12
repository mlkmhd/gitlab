# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Gitlab::Metrics::Subscribers::ClickHouse, :request_store, feature_category: :database do
  let(:subscriber) { described_class.new }
  let(:query) { ClickHouse::Client::Query.new(raw_query: 'SELECT 1') }
  let(:select_statistics) { { elapsed: 0.0012, rows_read: 120, bytes_read: 4096 } }
  let(:summary_statistics) do
    { read_rows: '30', read_bytes: '1024', written_rows: '0', written_bytes: '0', elapsed_ns: '1254667' }
  end

  def build_event(duration_ms:, statistics:)
    instance_double(
      ActiveSupport::Notifications::Event,
      payload: { query: query, database: :main, statistics: statistics },
      duration: duration_ms
    )
  end

  describe '.payload' do
    it 'returns an empty hash when no query was recorded' do
      expect(described_class.payload).to eq({})
    end

    it 'accumulates the totals of every recorded query' do
      allow(ClickHouse::ReadOnlyMarker).to receive(:active?).and_return(true, true, false)

      subscriber.sql(build_event(duration_ms: 100.0, statistics: select_statistics))
      subscriber.sql(build_event(duration_ms: 250.0, statistics: select_statistics))
      subscriber.sql(build_event(duration_ms: 50.0, statistics: summary_statistics))

      expect(described_class.payload).to eq(
        clickhouse_queries_count: 3,
        clickhouse_rows_read: 270,
        clickhouse_bytes_read: 9216,
        clickhouse_duration_s: 0.4,
        clickhouse_read_duration_s: 0.35,
        clickhouse_execute_duration_s: 0.05
      )
    end
  end

  describe '#sql' do
    it 'reads the SELECT statistics keys' do
      subscriber.sql(build_event(duration_ms: 100.0, statistics: select_statistics))

      expect(described_class.rows_read).to eq(120)
      expect(described_class.bytes_read).to eq(4096)
    end

    it 'reads the X-ClickHouse-Summary header keys' do
      subscriber.sql(build_event(duration_ms: 100.0, statistics: summary_statistics))

      expect(described_class.rows_read).to eq(30)
      expect(described_class.bytes_read).to eq(1024)
    end

    it 'counts the query and adds zeros when the statistics are missing' do
      subscriber.sql(build_event(duration_ms: 100.0, statistics: nil))
      subscriber.sql(build_event(duration_ms: 200.0, statistics: {}))

      expect(described_class.payload).to eq(
        clickhouse_queries_count: 2,
        clickhouse_rows_read: 0,
        clickhouse_bytes_read: 0,
        clickhouse_duration_s: 0.3,
        clickhouse_read_duration_s: 0.0,
        clickhouse_execute_duration_s: 0.3
      )
    end

    it 'rounds the duration to the instrumentation precision' do
      subscriber.sql(build_event(duration_ms: 123.4567891, statistics: select_statistics))

      expect(described_class.duration).to eq(0.123457)
    end

    context 'when the request store is not active' do
      before do
        allow(Gitlab::SafeRequestStore).to receive(:active?).and_return(false)
      end

      it 'does not record the query' do
        subscriber.sql(build_event(duration_ms: 100.0, statistics: select_statistics))

        expect(described_class.request_count).to eq(0)
        expect(described_class.payload).to eq({})
      end
    end

    context 'with a web transaction' do
      let(:transaction) { Gitlab::Metrics::WebTransaction.new({}) }

      before do
        allow(Gitlab::Metrics::WebTransaction).to receive(:current).and_return(transaction)
      end

      it 'observes the duration of a read query' do
        allow(ClickHouse::ReadOnlyMarker).to receive(:active?).and_return(true)

        expect(transaction).to receive(:observe)
          .with(:gitlab_clickhouse_duration_seconds, 0.1, { operation: :read })

        subscriber.sql(build_event(duration_ms: 100.0, statistics: select_statistics))
      end

      it 'observes the duration of an execute query' do
        expect(transaction).to receive(:observe)
          .with(:gitlab_clickhouse_duration_seconds, 0.1, { operation: :execute })

        subscriber.sql(build_event(duration_ms: 100.0, statistics: summary_statistics))
      end

      it 'defines the histogram with the operation label and buckets' do
        options = Gitlab::Metrics::Methods::MetricOptions.new

        expect(transaction).to receive(:observe) { |*, &block| options.evaluate(&block) }

        subscriber.sql(build_event(duration_ms: 100.0, statistics: summary_statistics))

        expect(options.label_keys).to eq([:operation])
        expect(options.buckets).to eq(described_class::DURATION_BUCKETS)
      end
    end

    context 'with a background transaction' do
      let(:transaction) { Gitlab::Metrics::BackgroundTransaction.new }

      before do
        allow(Gitlab::Metrics::BackgroundTransaction).to receive(:current).and_return(transaction)
      end

      it 'observes the duration' do
        expect(transaction).to receive(:observe)
          .with(:gitlab_clickhouse_duration_seconds, 0.1, { operation: :execute })

        subscriber.sql(build_event(duration_ms: 100.0, statistics: summary_statistics))
      end
    end

    context 'without a metrics transaction' do
      before do
        allow(Gitlab::Metrics).to receive(:current_transaction).and_return(nil)
      end

      it 'still records the query in the request store' do
        expect { subscriber.sql(build_event(duration_ms: 100.0, statistics: summary_statistics)) }.not_to raise_error

        expect(described_class.execute_duration).to eq(0.1)
      end
    end
  end

  describe 'subscription' do
    it 'receives the statistics set inside the instrumented block' do
      ActiveSupport::Notifications.instrument('sql.click_house', { query: query, database: :main }) do |payload|
        payload[:statistics] = { elapsed: 0.001, rows_read: 42, bytes_read: 336 }
      end

      expect(described_class.request_count).to eq(1)
      expect(described_class.rows_read).to eq(42)
      expect(described_class.bytes_read).to eq(336)
      expect(described_class.duration).to be > 0
    end

    it 'counts a query that raised inside the instrumented block with zero rows and bytes' do
      expect do
        ActiveSupport::Notifications.instrument('sql.click_house', { query: query, database: :main }) do
          raise ClickHouse::Client::DatabaseError, 'boom'
        end
      end.to raise_error(ClickHouse::Client::DatabaseError)

      expect(described_class.payload).to include(
        clickhouse_queries_count: 1,
        clickhouse_rows_read: 0,
        clickhouse_bytes_read: 0
      )
    end

    context 'with a query run through the client', click_house: :without_migrations do
      it 'records the query the client ran' do
        count_before = described_class.request_count
        rows_before = described_class.rows_read
        duration_before = described_class.duration

        ClickHouse::Client.select('SELECT 1', :main)

        expect(described_class.request_count).to eq(count_before + 1)
        expect(described_class.rows_read).to be >= rows_before + 1
        expect(described_class.duration).to be > duration_before
      end

      it 'records select as read and execute as execute' do
        read_before = described_class.read_duration
        execute_before = described_class.execute_duration

        ClickHouse::Client.select('SELECT 1', :main)

        expect(described_class.read_duration).to be > read_before
        expect(described_class.execute_duration).to eq(execute_before)

        ClickHouse::Client.execute('SELECT 1', :main)

        expect(described_class.execute_duration).to be > execute_before
      end
    end
  end
end
