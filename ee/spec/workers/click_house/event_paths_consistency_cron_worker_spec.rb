# frozen_string_literal: true

require 'spec_helper'

RSpec.describe ClickHouse::EventPathsConsistencyCronWorker, feature_category: :value_stream_management do
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
        allow(ClickHouse::Client).to receive(:database_configured?).and_return(false)

        expect(worker).not_to receive(:log_extra_metadata_on_done)

        worker.perform
      end
    end

    context 'when ClickHouse is available', :click_house do
      let_it_be(:connection) { ClickHouse::Connection.new(:main) }
      let_it_be_with_reload(:namespace1) { create(:group) }
      let_it_be_with_reload(:namespace2) { create(:project).project_namespace }
      let_it_be_with_reload(:namespace_with_updated_parent) { create(:group, parent: create(:group)) }

      let(:leftover_paths) { connection.select('SELECT DISTINCT path FROM events FINAL').pluck('path') }
      let(:deleted_namespace_id) { namespace_with_updated_parent.id + 1 }
      let(:mutations_counter) { instance_double(Prometheus::Client::Counter, increment: nil) }
      let(:counter_labels) { { worker: described_class.name } }

      before do
        allow(Gitlab::Metrics).to receive(:counter).and_call_original
        allow(Gitlab::Metrics).to receive(:counter)
          .with(:gitlab_clickhouse_consistency_mutations_total, anything)
          .and_return(mutations_counter)

        insert_query = <<~SQL
      INSERT INTO events (id, path) VALUES
      (1, '#{namespace1.traversal_path(with_organization: false)}'),
      (2, '#{namespace2.traversal_path(with_organization: false)}'),
      (3, '#{namespace1.id}/#{namespace_with_updated_parent.id}/'),
      (4, '#{deleted_namespace_id}/'),
      (5, '#{deleted_namespace_id}/')
        SQL

        connection.execute(insert_query)
      end

      shared_examples 'repairs the inconsistent paths' do
        it 'fixes all inconsistent records in ClickHouse', :aggregate_failures do
          worker.perform

          paths = [
            namespace1.traversal_path(with_organization: false),
            namespace2.traversal_path(with_organization: false),
            namespace_with_updated_parent.traversal_path(with_organization: false)
          ]

          expect(leftover_paths).to match_array(paths)

          # the next job starts from the beginning of the table
          expect(ClickHouse::SyncCursor.cursor_for(:event_namespace_paths_consistency_check)).to eq(0)
          expect(mutations_counter).to have_received(:increment).with(counter_labels).exactly(4).times
        end

        context 'when the table is empty' do
          it 'does not do anything' do
            connection.execute('TRUNCATE TABLE event_namespace_paths')

            expect { worker.perform }.not_to change { connection.select('SELECT * FROM events FINAL ORDER BY id') }
            expect(mutations_counter).not_to have_received(:increment)
          end
        end

        context 'when the previous job was not finished' do
          it 'continues the processing from the cursor' do
            ClickHouse::SyncCursor.update_cursor_for(:event_namespace_paths_consistency_check, deleted_namespace_id)

            worker.perform

            paths = [
              namespace1.traversal_path(with_organization: false),
              namespace2.traversal_path(with_organization: false),
              "#{namespace1.id}/#{namespace_with_updated_parent.id}/"
            ]
            # the previous records should remain
            expect(leftover_paths).to match_array(paths)
          end
        end

        context 'when processing stops due to the record clean up limit' do
          it 'stores the last processed id value' do
            stub_const("#{described_class}::MAX_RECORD_MODIFICATIONS", 1)
            stub_const("#{ClickHouse::Concerns::ConsistencyWorker}::POSTGRESQL_BATCH_SIZE", 1)

            expect(worker).to receive(:log_extra_metadata_on_done).with(:result,
              { status: :limit_reached, modifications: 1 })

            worker.perform

            paths = [
              namespace1.traversal_path(with_organization: false),
              namespace2.traversal_path(with_organization: false),
              namespace_with_updated_parent.traversal_path(with_organization: false),
              "#{deleted_namespace_id}/"
            ]

            expect(leftover_paths).to match_array(paths)
            expect(ClickHouse::SyncCursor.cursor_for(:event_namespace_paths_consistency_check))
              .to eq(namespace_with_updated_parent.id)
          end
        end

        context 'when the processing stops due to time limit' do
          it 'returns over_time status' do
            stub_const("#{ClickHouse::Concerns::ConsistencyWorker}::POSTGRESQL_BATCH_SIZE", 1)

            # the first two namespace ids are consistent, the third needs an update
            allow_next_instance_of(Gitlab::Metrics::RuntimeLimiter) do |runtime_limiter|
              allow(runtime_limiter).to receive(:over_time?).and_return(false, false, true)
            end

            expect(worker).to receive(:log_extra_metadata_on_done).with(:result,
              { status: :over_time, modifications: 1 })

            worker.perform
          end
        end
      end

      shared_context 'with two namespaces to update' do
        let_it_be(:moved_namespace1) { create(:group, parent: create(:group)) }
        let_it_be(:moved_namespace2) { create(:group, parent: create(:group)) }

        let(:fixed_paths) do
          [
            moved_namespace1.traversal_path(with_organization: false),
            moved_namespace2.traversal_path(with_organization: false)
          ]
        end

        before do
          connection.execute('TRUNCATE TABLE events')
          connection.execute('TRUNCATE TABLE event_namespace_paths')
          connection.execute(<<~SQL)
            INSERT INTO events (id, path) VALUES
            (1, '#{namespace1.id}/#{moved_namespace1.id}/'),
            (2, '#{namespace1.id}/#{moved_namespace2.id}/')
          SQL

          stub_const("#{described_class}::MAX_RECORD_MODIFICATIONS", 1)
        end
      end

      context 'when strict caps are enabled' do
        before do
          stub_feature_flags(clickhouse_consistency_workers_strict_caps: true)
        end

        it_behaves_like 'repairs the inconsistent paths'

        context 'when two namespaces need an update' do
          include_context 'with two namespaces to update'

          # The worker visits the slice in numeric namespace_id order, not string order of the paths.
          let(:first_namespace) { [moved_namespace1, moved_namespace2].min_by(&:id) }

          let(:second_namespace) { ([moved_namespace1, moved_namespace2] - [first_namespace]).first }

          it 'stops collecting at the cap and updates the first namespace only' do
            expect(worker).to receive(:log_extra_metadata_on_done).with(:result,
              { status: :limit_reached, modifications: 1 })

            worker.perform

            expect(leftover_paths).to contain_exactly(
              first_namespace.traversal_path(with_organization: false),
              "#{namespace1.id}/#{second_namespace.id}/"
            )
            expect(ClickHouse::SyncCursor.cursor_for(:event_namespace_paths_consistency_check))
              .to eq(first_namespace.id)
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

          it 'stops at the first mutation whose renewal fails and skips the cursor write' do
            allow(ClickHouse::SyncCursor).to receive(:update_cursor_for).and_call_original
            allow_next_instance_of(Gitlab::ExclusiveLeaseHelpers::SleepingLock) do |lease|
              allow(lease).to receive(:renew).and_return(true, false)
            end

            expect { worker.perform }.to raise_error(ClickHouse::Concerns::ConsistencyWorker::LeaseLostError)

            expect(mutations_counter).to have_received(:increment).with(counter_labels).once
            expect(ClickHouse::SyncCursor).not_to have_received(:update_cursor_for)
          end

          it 'issues no mutation when the lease was lost during collection' do
            allow_next_instance_of(Gitlab::ExclusiveLeaseHelpers::SleepingLock) do |lease|
              allow(lease).to receive(:renew).and_return(false)
            end

            expect { worker.perform }.to raise_error(ClickHouse::Concerns::ConsistencyWorker::LeaseLostError)

            expect(mutations_counter).not_to have_received(:increment)
            expect(leftover_paths).to contain_exactly(
              "#{namespace1.id}/#{moved_namespace1.id}/", "#{namespace1.id}/#{moved_namespace2.id}/"
            )
          end
        end

        context 'when the path order differs from the namespace_id order' do
          let(:lower_id) { 1_000_000_000_001 }
          let(:higher_id) { 1_000_000_000_002 }
          let(:lower_id_path) { "9/#{lower_id}/" }
          let(:higher_id_path) { "1/#{higher_id}/" }

          before do
            connection.execute('TRUNCATE TABLE events')
            connection.execute('TRUNCATE TABLE event_namespace_paths')
            connection.execute("INSERT INTO events (id, path) VALUES (1, '#{lower_id_path}'), (2, '#{higher_id_path}')")

            stub_const("#{described_class}::MAX_RECORD_MODIFICATIONS", 1)
          end

          it 'processes the lower id first and repairs the rest on the next run', :aggregate_failures do
            worker.perform

            expect(leftover_paths).to contain_exactly(higher_id_path)
            expect(ClickHouse::SyncCursor.cursor_for(:event_namespace_paths_consistency_check)).to eq(lower_id)

            described_class.new.perform

            # leftover_paths is memoized, so read the table again
            expect(connection.select('SELECT DISTINCT path FROM events FINAL').pluck('path')).to be_empty
            expect(ClickHouse::SyncCursor.cursor_for(:event_namespace_paths_consistency_check)).to eq(higher_id)
          end
        end

        context 'when the lease was lost and nothing was collected' do
          it 'raises without writing the cursor' do
            connection.execute('TRUNCATE TABLE event_namespace_paths')
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

        it_behaves_like 'repairs the inconsistent paths'

        context 'when two namespaces need an update' do
          include_context 'with two namespaces to update'

          it 'updates the whole slice and only reports the limit' do
            expect(worker).to receive(:log_extra_metadata_on_done).with(:result,
              { status: :limit_reached, modifications: 2 })

            worker.perform

            expect(leftover_paths).to match_array(fixed_paths)
            expect(mutations_counter).to have_received(:increment).with(counter_labels).exactly(4).times
          end

          it 'releases the lease before the mutations run' do
            allow(worker).to receive(:process_collected_values).and_wrap_original do |original|
              expect { described_class.new.perform }.not_to raise_error

              original.call
            end

            worker.perform

            expect(mutations_counter).to have_received(:increment).exactly(8).times
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
