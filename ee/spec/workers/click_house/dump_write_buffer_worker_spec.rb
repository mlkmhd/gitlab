# frozen_string_literal: true

require 'spec_helper'

RSpec.describe ClickHouse::DumpWriteBufferWorker, feature_category: :value_stream_management do
  include ExclusiveLeaseHelpers

  let(:job) { described_class.new }
  let(:perform) { job.perform(table_name) }
  let(:table_name) { 'ai_usage_events' }
  let(:pending_gauge_double) { instance_double(Prometheus::Client::Gauge) }
  let(:requeued_counter_double) { instance_double(Prometheus::Client::Counter) }
  let(:lease_key) { "ClickHouse::DumpWriteBufferWorker:#{table_name}" }

  before do
    allow(Gitlab::Metrics).to receive(:gauge).and_call_original
    allow(Gitlab::Metrics).to receive(:gauge)
      .with(:gitlab_clickhouse_write_buffer_pending, anything, {}, :max)
      .and_return(pending_gauge_double)
    allow(pending_gauge_double).to receive(:set)
    allow(Gitlab::Metrics).to receive(:counter).and_call_original
    allow(Gitlab::Metrics).to receive(:counter)
      .with(:gitlab_clickhouse_write_buffer_requeued_total, anything)
      .and_return(requeued_counter_double)
    allow(requeued_counter_double).to receive(:increment)
  end

  context 'when ClickHouse is disabled for analytics' do
    before do
      stub_application_setting(use_clickhouse_for_analytics: false)
    end

    it 'does nothing after setting the gauge' do
      expect(Gitlab::Metrics::RuntimeLimiter).not_to receive(:new)

      perform
    end

    it 'still sets the pending gauge before returning so the series does not freeze' do
      allow(ClickHouse::WriteBuffer).to receive(:pending).with(table_name).and_return(5)

      expect(pending_gauge_double).to receive(:set).with({ table: table_name }, 5)

      perform
    end
  end

  context 'when ClickHouse is enabled', :click_house, :clean_gitlab_redis_shared_state do
    let(:connection) { ClickHouse::Connection.new(:main) }

    subject(:inserted_records) { connection.select("SELECT * FROM #{table_name} FINAL ORDER BY user_id ASC") }

    before do
      stub_application_setting(use_clickhouse_for_analytics: true)
    end

    it 'does not insert anything' do
      perform

      expect(inserted_records).to be_empty
    end

    describe 'pending gauge' do
      it 'sets the gauge to 0 when the write buffer is empty before draining' do
        expect(pending_gauge_double).to receive(:set).with({ table: table_name }, 0)

        perform
      end

      it 'sets the gauge to the pending count before draining' do
        ClickHouse::WriteBuffer.add(table_name, { user_id: 1 })
        ClickHouse::WriteBuffer.add(table_name, { user_id: 2 })

        expect(pending_gauge_double).to receive(:set).with({ table: table_name }, 2)

        perform
      end
    end

    context 'when data is present' do
      before do
        ClickHouse::WriteBuffer.add(table_name, { user_id: 1 })
        ClickHouse::WriteBuffer.add(table_name, { user_id: 2 })
        ClickHouse::WriteBuffer.add(table_name, { user_id: 3 })
      end

      it 'inserts all rows' do
        status = perform

        expect(status).to eq({ status: :processed, inserted_rows: 3 })

        expect(inserted_records).to match([
          hash_including('user_id' => 1),
          hash_including('user_id' => 2),
          hash_including('user_id' => 3)
        ])
      end

      it 'holds a per-table lease while dumping' do
        expect(job).to receive(:in_lock)
          .with(lease_key, ttl: described_class::LEASE_TTL, retries: 0)
          .and_call_original

        expect(perform).to eq({ status: :processed, inserted_rows: 3 })
      end

      context 'when another run holds the lease for the table' do
        before do
          stub_exclusive_lease_taken(lease_key, timeout: described_class::LEASE_TTL)
        end

        it 'skips the run without touching the buffer or ClickHouse' do
          expect(ClickHouse::WriteBuffer).not_to receive(:pop)
          expect(ClickHouse::Client).not_to receive(:insert_csv)

          expect(perform).to eq({ status: :skipped, inserted_rows: 0 })

          expect(ClickHouse::WriteBuffer.pending(table_name)).to eq(3)
        end
      end

      context 'when the insert fails' do
        before do
          allow(ClickHouse::Client).to receive(:insert_csv)
            .and_raise(ClickHouse::Client::DatabaseError, 'insert failed')
        end

        it 'puts the popped rows back in their original order and re-raises' do
          allow(job).to receive(:log_extra_metadata_on_done).and_call_original
          expect(job).to receive(:log_extra_metadata_on_done).with(:requeued_rows, 3)
          expect(requeued_counter_double).to receive(:increment).with({ table: table_name }, 3)

          expect { perform }.to raise_error(ClickHouse::Client::DatabaseError)

          expect(ClickHouse::WriteBuffer.pop(table_name, 100)).to eq([{ user_id: 1 }, { user_id: 2 }, { user_id: 3 }])
        end

        context 'when the connection is refused' do
          before do
            allow(ClickHouse::Client).to receive(:insert_csv).and_raise(Errno::ECONNREFUSED)
          end

          it 'puts the popped rows back and re-raises' do
            expect { perform }.to raise_error(Errno::ECONNREFUSED)

            expect(ClickHouse::WriteBuffer.pending(table_name)).to eq(3)
          end
        end

        context 'when the request times out after the batch was sent' do
          before do
            allow(ClickHouse::Client).to receive(:insert_csv).and_raise(Net::ReadTimeout)
          end

          it 're-raises without putting the rows back' do
            expect(ClickHouse::WriteBuffer).not_to receive(:add_all)
            expect(requeued_counter_double).not_to receive(:increment)

            expect { perform }.to raise_error(Net::ReadTimeout)

            expect(ClickHouse::WriteBuffer.pending(table_name)).to eq(0)
          end
        end

        context 'when putting the rows back fails too' do
          before do
            allow(ClickHouse::WriteBuffer).to receive(:add_all).and_raise(Redis::CannotConnectError)
          end

          it 'tracks the lost rows and re-raises the insert error' do
            allow(job).to receive(:log_extra_metadata_on_done).and_call_original
            expect(job).to receive(:log_extra_metadata_on_done).with(:lost_rows, 3)
            expect(Gitlab::ErrorTracking).to receive(:track_exception)
              .with(an_instance_of(Redis::CannotConnectError), table_name: table_name, lost_rows: 3)
            expect(requeued_counter_double).not_to receive(:increment)

            expect { perform }.to raise_error(ClickHouse::Client::DatabaseError)

            expect(ClickHouse::WriteBuffer.pending(table_name)).to eq(0)
          end
        end

        context 'when the counter raises after the rows were put back' do
          before do
            allow(requeued_counter_double).to receive(:increment).and_raise(StandardError, 'metrics down')
          end

          it 'tracks the counter error and still re-raises the insert error' do
            allow(job).to receive(:log_extra_metadata_on_done).and_call_original
            expect(job).not_to receive(:log_extra_metadata_on_done).with(:lost_rows, anything)
            expect(Gitlab::ErrorTracking).to receive(:track_exception)
              .with(an_instance_of(StandardError), table_name: table_name).once

            expect { perform }.to raise_error(ClickHouse::Client::DatabaseError)

            expect(ClickHouse::WriteBuffer.pending(table_name)).to eq(3)
          end
        end

        context 'when the protection flag is disabled' do
          before do
            stub_feature_flags(clickhouse_write_buffer_dump_protection: false)
          end

          it 're-raises and leaves the popped rows out of the buffer, as before the flag' do
            expect(ClickHouse::WriteBuffer).not_to receive(:add_all)
            expect(requeued_counter_double).not_to receive(:increment)

            expect { perform }.to raise_error(ClickHouse::Client::DatabaseError)

            expect(ClickHouse::WriteBuffer.pending(table_name)).to eq(0)
          end
        end
      end

      context 'when the protection flag is disabled' do
        before do
          stub_feature_flags(clickhouse_write_buffer_dump_protection: false)
        end

        it 'inserts all rows without taking a lease' do
          expect(job).not_to receive(:in_lock)

          expect(perform).to eq({ status: :processed, inserted_rows: 3 })
        end
      end

      context 'when looping twice' do
        it 'inserts all rows' do
          stub_const("#{described_class.name}::BATCH_SIZE", 2)

          status = perform

          expect(status).to eq({ status: :processed, inserted_rows: 3 })
        end
      end

      context 'when pinging ClickHouse fails' do
        it 'does not take anything from buffer' do
          allow_next_instance_of(ClickHouse::Connection) do |connection|
            expect(connection).to receive(:ping).and_raise(Errno::ECONNREFUSED)
          end

          expect { perform }.to raise_error(Errno::ECONNREFUSED)

          expect(ClickHouse::WriteBuffer.pop(table_name, 100).size).to eq(3)
        end
      end

      context 'when time limit is up' do
        it 'returns over_time status' do
          stub_const("#{described_class.name}::BATCH_SIZE", 1)

          allow_next_instance_of(Gitlab::Metrics::RuntimeLimiter) do |limiter|
            allow(limiter).to receive(:over_time?).and_return(false, true)
          end

          status = perform

          expect(status).to eq({ status: :over_time, inserted_rows: 2 })

          expect(inserted_records).to match([
            hash_including('user_id' => 1),
            hash_including('user_id' => 2)
          ])
        end
      end
    end

    context 'when data has 2 different sets of fields', :freeze_time do
      let!(:usage1_hash) do
        {
          user_id: 1,
          timestamp: 1.day.ago.to_f,
          event: 1
        }
      end

      let!(:usage2_hash) do
        {
          user_id: 2,
          timestamp: 2.days.ago.to_f,
          event: 2,
          namespace_path: '2/'
        }
      end

      before do
        ::ClickHouse::WriteBuffer.add(table_name, usage1_hash)
        ::ClickHouse::WriteBuffer.add(table_name, usage2_hash)
      end

      it 'runs separate insert query for each attributes group' do
        expect(ClickHouse::Client).to receive(:insert_csv).twice.and_call_original

        status = perform

        expect(status).to eq({ status: :processed, inserted_rows: 2 })

        expect(inserted_records).to match([
          hash_including('user_id' => 1),
          hash_including('user_id' => 2)
        ])
      end

      context 'when the insert of the second group fails' do
        before do
          allow(ClickHouse::Client).to receive(:insert_csv).and_wrap_original do |original, query, *args|
            raise ClickHouse::Client::DatabaseError, 'insert failed' if query.include?('namespace_path')

            original.call(query, *args)
          end
        end

        it 'keeps the inserted group out of the buffer and puts back only the failed one' do
          expect(requeued_counter_double).to receive(:increment).with({ table: table_name }, 1)

          expect { perform }.to raise_error(ClickHouse::Client::DatabaseError)

          expect(inserted_records).to match([hash_including('user_id' => 1)])
          expect(ClickHouse::WriteBuffer.pop(table_name, 100)).to eq([usage2_hash])
        end
      end
    end
  end
end
