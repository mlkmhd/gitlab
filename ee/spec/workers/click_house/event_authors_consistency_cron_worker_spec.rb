# frozen_string_literal: true

require 'spec_helper'

RSpec.describe ClickHouse::EventAuthorsConsistencyCronWorker, feature_category: :value_stream_management do
  let(:worker) { described_class.new }

  context 'when ClickHouse is disabled' do
    before do
      stub_application_setting(use_clickhouse_for_analytics: false)
    end

    it 'does nothing' do
      expect(worker).not_to receive(:log_extra_metadata_on_done)

      worker.perform
    end
  end

  context 'when ClickHouse is enabled' do
    before do
      stub_application_setting(use_clickhouse_for_analytics: true)
    end

    context 'when ClickHouse is not configured' do
      it 'does nothing' do
        allow(Gitlab::ClickHouse).to receive(:configured?).and_return(false)

        expect(worker).not_to receive(:log_extra_metadata_on_done)

        worker.perform
      end
    end

    context 'when ClickHouse is available', :click_house do
      let_it_be(:connection) { ClickHouse::Connection.new(:main) }
      let_it_be_with_reload(:user1) { create(:user) }
      let_it_be_with_reload(:user2) { create(:user) }

      let(:leftover_author_ids) { connection.select('SELECT DISTINCT author_id FROM events FINAL').pluck('author_id') }
      let(:deleted_user_id1) { user2.id + 1 }
      let(:deleted_user_id2) { user2.id + 2 }
      let(:mutations_counter) { instance_double(Prometheus::Client::Counter, increment: nil) }
      let(:counter_labels) { { worker: described_class.name } }

      before do
        allow(Gitlab::Metrics).to receive(:counter).and_call_original
        allow(Gitlab::Metrics).to receive(:counter)
          .with(:gitlab_clickhouse_consistency_mutations_total, anything)
          .and_return(mutations_counter)

        insert_query = <<~SQL
      INSERT INTO events (id, author_id) VALUES
      (1, #{user1.id}),
      (2, #{user2.id}),
      (3, #{deleted_user_id1}),
      (4, #{deleted_user_id1}),
      (5, #{deleted_user_id2})
        SQL

        connection.execute(insert_query)
      end

      shared_examples 'cleans up the inconsistent authors' do
        it 'cleans up all inconsistent records in ClickHouse', :aggregate_failures do
          worker.perform

          expect(leftover_author_ids).to contain_exactly(user1.id, user2.id)

          # the next job starts from the beginning of the table
          expect(ClickHouse::SyncCursor.cursor_for(:event_authors_consistency_check)).to eq(0)
          expect(mutations_counter).to have_received(:increment).with(counter_labels).exactly(2).times
        end

        context 'when the previous job was not finished' do
          it 'continues the processing from the cursor' do
            ClickHouse::SyncCursor.update_cursor_for(:event_authors_consistency_check, deleted_user_id2)

            worker.perform

            # the previous records should remain
            expect(leftover_author_ids).to contain_exactly(user1.id, user2.id, deleted_user_id1)
          end
        end

        context 'when processing stops due to the record clean up limit' do
          it 'stores the last processed id value' do
            User.where(id: [user1.id, user2.id]).delete_all

            stub_const("#{described_class}::MAX_AUTHOR_DELETIONS", 2)
            stub_const("#{ClickHouse::Concerns::ConsistencyWorker}::POSTGRESQL_BATCH_SIZE", 1)

            expect(worker).to receive(:log_extra_metadata_on_done).with(:result,
              { status: :limit_reached, modifications: 2 })

            worker.perform

            expect(leftover_author_ids).to contain_exactly(deleted_user_id1, deleted_user_id2)
            expect(ClickHouse::SyncCursor.cursor_for(:event_authors_consistency_check)).to eq(user2.id)
          end
        end

        context 'when time limit is reached' do
          it 'stops the processing earlier' do
            stub_const("#{ClickHouse::Concerns::ConsistencyWorker}::POSTGRESQL_BATCH_SIZE", 1)

            # stop at the third author_id
            allow_next_instance_of(Gitlab::Metrics::RuntimeLimiter) do |runtime_limiter|
              allow(runtime_limiter).to receive(:over_time?).and_return(false, false, true)
            end
            expect(worker).to receive(:log_extra_metadata_on_done).with(:result,
              { status: :over_time, modifications: 1 })

            worker.perform

            expect(leftover_author_ids).to contain_exactly(user1.id, user2.id, deleted_user_id2)
          end

          context 'when the last batch has no missing authors' do
            it 'stores the last scanned id as the cursor' do
              stub_const("#{ClickHouse::Concerns::ConsistencyWorker}::POSTGRESQL_BATCH_SIZE", 1)

              allow_next_instance_of(Gitlab::Metrics::RuntimeLimiter) do |runtime_limiter|
                allow(runtime_limiter).to receive(:over_time?).and_return(true)
              end
              expect(worker).to receive(:log_extra_metadata_on_done).with(:result,
                { status: :over_time, modifications: 0 })

              worker.perform

              expect(leftover_author_ids).to contain_exactly(user1.id, user2.id, deleted_user_id1, deleted_user_id2)
              expect(ClickHouse::SyncCursor.cursor_for(:event_authors_consistency_check)).to eq(user1.id)
            end
          end
        end
      end

      shared_context 'when all authors exist' do
        before do
          connection.execute('TRUNCATE TABLE events')
          connection.execute('TRUNCATE TABLE event_authors')
          connection.execute("INSERT INTO events (id, author_id) VALUES (1, #{user1.id}), (2, #{user2.id})")
        end
      end

      context 'when strict caps are enabled' do
        before do
          stub_feature_flags(clickhouse_consistency_workers_strict_caps: true)
        end

        it_behaves_like 'cleans up the inconsistent authors'

        it 'stops collecting at the cap and stores the last deleted id' do
          stub_const("#{described_class}::MAX_AUTHOR_DELETIONS", 1)

          expect(worker).to receive(:log_extra_metadata_on_done).with(:result,
            { status: :limit_reached, modifications: 1 })

          worker.perform

          expect(leftover_author_ids).to contain_exactly(user1.id, user2.id, deleted_user_id2)
          expect(ClickHouse::SyncCursor.cursor_for(:event_authors_consistency_check)).to eq(deleted_user_id1)
          expect(mutations_counter).to have_received(:increment).with(counter_labels).exactly(2).times
        end

        it 'holds the lease through the mutations and the cursor write' do
          allow(worker).to receive(:process_collected_values).and_wrap_original do |original|
            expect_second_run_to_find_the_lease_taken

            original.call
          end
          allow(ClickHouse::SyncCursor).to receive(:update_cursor_for).and_wrap_original do |original, *args|
            expect_second_run_to_find_the_lease_taken

            original.call(*args)
          end

          worker.perform

          expect(mutations_counter).to have_received(:increment).exactly(2).times
        end

        it 'issues no mutation when the lease was lost during collection' do
          allow_next_instance_of(Gitlab::ExclusiveLeaseHelpers::SleepingLock) do |lease|
            allow(lease).to receive(:renew).and_return(false)
          end

          expect { worker.perform }.to raise_error(ClickHouse::Concerns::ConsistencyWorker::LeaseLostError)

          expect(mutations_counter).not_to have_received(:increment)
          expect(leftover_author_ids).to contain_exactly(user1.id, user2.id, deleted_user_id1, deleted_user_id2)
        end

        context 'when all authors exist' do
          include_context 'when all authors exist'

          it 'issues no mutations' do
            expect(worker).to receive(:log_extra_metadata_on_done).with(:result,
              { status: :processed, modifications: 0 })

            worker.perform

            expect(mutations_counter).not_to have_received(:increment)
          end

          it 'raises without writing the cursor when the lease was lost' do
            allow(ClickHouse::SyncCursor).to receive(:update_cursor_for).and_call_original
            allow_next_instance_of(Gitlab::ExclusiveLeaseHelpers::SleepingLock) do |lease|
              allow(lease).to receive(:renew).and_return(false)
            end

            expect { worker.perform }.to raise_error(ClickHouse::Concerns::ConsistencyWorker::LeaseLostError)

            expect(ClickHouse::SyncCursor).not_to have_received(:update_cursor_for)
          end
        end

        context 'when another run holds the lease' do
          it 'logs lease_taken and issues nothing' do
            hold_the_lease do
              expect(worker).to receive(:log_extra_metadata_on_done).with(:result,
                { status: :lease_taken, modifications: 0 })

              worker.perform
            end

            expect(mutations_counter).not_to have_received(:increment)
          end
        end
      end

      context 'when strict caps are disabled' do
        before do
          stub_feature_flags(clickhouse_consistency_workers_strict_caps: false)
        end

        it_behaves_like 'cleans up the inconsistent authors'

        it 'deletes the whole slice and only reports the limit' do
          stub_const("#{described_class}::MAX_AUTHOR_DELETIONS", 1)

          expect(worker).to receive(:log_extra_metadata_on_done).with(:result,
            { status: :limit_reached, modifications: 2 })

          worker.perform

          expect(leftover_author_ids).to contain_exactly(user1.id, user2.id)
          expect(mutations_counter).to have_received(:increment).with(counter_labels).exactly(2).times
        end

        context 'when all authors exist' do
          include_context 'when all authors exist'

          it 'still issues the two DELETE mutations' do
            worker.perform

            expect(mutations_counter).to have_received(:increment).with(counter_labels).exactly(2).times
          end
        end

        context 'when another run holds the lease' do
          it 'raises' do
            hold_the_lease do
              expect { worker.perform }.to raise_error(Gitlab::ExclusiveLeaseHelpers::FailedToObtainLockError)
            end
          end
        end
      end

      def expect_second_run_to_find_the_lease_taken
        second_run = described_class.new

        expect(second_run).to receive(:log_extra_metadata_on_done).with(:result,
          { status: :lease_taken, modifications: 0 })

        second_run.perform
      end

      def hold_the_lease
        lease = Gitlab::ExclusiveLease.new(described_class.to_s, timeout: 60)
        lease.try_obtain

        yield
      ensure
        lease.cancel
      end
    end
  end
end
