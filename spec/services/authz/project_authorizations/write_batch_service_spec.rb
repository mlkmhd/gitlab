# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Authz::ProjectAuthorizations::WriteBatchService, feature_category: :permissions do
  let_it_be(:user) { create(:user) }
  let_it_be(:other_user) { create(:user) }
  let_it_be(:projects) { create_list(:project, 4) }

  let(:project_ids) { projects.map(&:id) }

  def rows_for(user)
    ProjectAuthorization.where(user: user).pluck(:project_id, :access_level)
  end

  before do
    ProjectAuthorization.delete_all
  end

  describe '.unchanged?' do
    using RSpec::Parameterized::TableSyntax

    where(:levels, :level, :unchanged) do
      [30]     | 30                         | true
      []       | nil                        | true
      []       | Gitlab::Access::NO_ACCESS  | true
      [30]     | 40                         | false
      [30, 30] | 30                         | false
      [30]     | nil                        | false
    end

    with_them do
      it { expect(described_class.unchanged?(levels, level)).to be(unchanged) }
    end
  end

  describe '.lock_sql' do
    it 'locks on the user IDs' do
      expect(described_class.lock_sql([3, 1, 3])).to include('ARRAY[1,3]')
    end

    it 'raises for a user ID too large for an int4 key' do
      expect { described_class.lock_sql([1, described_class::MAX_LOCK_KEY + 1]) }
        .to raise_error(ArgumentError, /too large/)
    end
  end

  describe '.wait_for_writers' do
    it 'takes the shared locks for the users' do
      expect(ProjectAuthorization.connection).to receive(:execute).and_call_original
      expect(ProjectAuthorization.connection).to receive(:execute)
        .with(/pg_advisory_xact_lock_shared/).and_call_original

      described_class.wait_for_writers([user.id])
    end

    it 'does nothing for no users' do
      expect(ProjectAuthorization.connection).not_to receive(:execute)

      described_class.wait_for_writers([])
    end

    it 'takes at most BATCH_SIZE users per transaction' do
      stub_const("#{described_class}::BATCH_SIZE", 1)
      locks = []
      allow(ProjectAuthorization.connection).to receive(:execute).and_call_original
      allow(ProjectAuthorization.connection).to receive(:execute).with(/pg_advisory_xact_lock_shared/) do
        locks << ProjectAuthorization.connection.current_transaction
      end

      described_class.wait_for_writers([user.id, other_user.id, user.id])

      expect(locks.size).to eq(2)
      expect(locks.uniq.size).to eq(2)
    end

    it 'refuses to run inside a transaction' do
      ProjectAuthorization.transaction do
        expect { described_class.wait_for_writers([user.id]) }
          .to raise_error(RuntimeError, /outside a transaction/)
      end
    end
  end

  describe '#initialize' do
    it 'needs exactly one of user_id and project_id' do
      expect { described_class.new }.to raise_error(ArgumentError)
      expect { described_class.new(user_id: 1, project_id: 1) }.to raise_error(ArgumentError)
    end
  end

  describe '#execute' do
    context 'for one user' do
      subject(:service) { described_class.new(user_id: user.id) }

      before do
        ProjectAuthorization.insert_all([
          { user_id: user.id, project_id: projects[0].id, access_level: 30, is_unique: true },
          { user_id: user.id, project_id: projects[1].id, access_level: 30, is_unique: true },
          { user_id: user.id, project_id: projects[2].id, access_level: 20, is_unique: true }
        ])
        ProjectAuthorization.insert_all([
          { user_id: user.id, project_id: projects[2].id, access_level: 10, is_unique: false }
        ])
      end

      it 'adds, changes, removes and rewrites duplicates to match the calculation, and leaves others alone' do
        levels = { projects[0].id => 30, projects[1].id => 40, projects[2].id => 20, projects[3].id => 10 }

        result = service.execute(project_ids) { |ids| levels.slice(*ids) }

        expect(rows_for(user)).to contain_exactly(
          [projects[0].id, 30], [projects[1].id, 40], [projects[2].id, 20], [projects[3].id, 10]
        )
        expect(result).to have_attributes(rows_added: 3, rows_deleted: 3)
      end

      it 'removes rows the calculation no longer grants' do
        service.execute(project_ids.first(2)) { |_| { projects[0].id => Gitlab::Access::NO_ACCESS } }

        expect(rows_for(user).map(&:first)).to contain_exactly(projects[2].id, projects[2].id)
      end

      it "doesn't touch rows outside the given IDs" do
        service.execute([projects[3].id]) { |_| {} }

        expect(rows_for(user).size).to eq(4)
      end

      it 'takes the lock before calculating, and calculates inside the transaction' do
        queries = []
        callback = ->(*, payload) { queries << payload[:sql] }

        ActiveSupport::Notifications.subscribed(callback, 'sql.active_record') do
          service.execute([projects[0].id]) do |ids|
            queries << :calculate
            expect(ProjectAuthorization.inside_transaction?).to be(true)

            { ids.first => 40 }
          end
        end

        lock = queries.index { |sql| sql.is_a?(String) && sql.include?('pg_advisory_xact_lock') }
        expect(lock).to be < queries.index(:calculate)
      end

      it 'retries a chunk whose lock times out, then gives up' do
        calls = 0
        allow(ProjectAuthorization.connection).to receive(:execute).and_call_original
        allow(ProjectAuthorization.connection).to receive(:execute).with(/pg_advisory_xact_lock/) do
          calls += 1
          raise ActiveRecord::LockWaitTimeout
        end

        expect { service.execute([projects[0].id]) { |_| {} } }.to raise_error(ActiveRecord::LockWaitTimeout)
        expect(calls).to eq(described_class::LOCK_ATTEMPTS)
      end

      it 'publishes added and removed notifications for the changed pairs, after the commit' do
        events = []
        allow(Gitlab::EventStore).to receive(:publish_group) do |group|
          expect(ProjectAuthorization.inside_transaction?).to be(false)
          events.concat(group)
        end

        service.execute(project_ids) { |_| { projects[3].id => 30 } }

        removed = events.grep(ProjectAuthorizations::AuthorizationsRemovedEvent).map(&:data)
        added = events.grep(ProjectAuthorizations::AuthorizationsAddedEvent).map(&:data)
        expect(removed).to match_array(
          projects.first(3).map { |project| { project_id: project.id, user_ids: [user.id] } }
        )
        expect(added).to contain_exactly(
          { project_ids: match_array(project_ids), user_ids: [user.id] }
        )
      end

      it 'publishes nothing for duplicates rewritten at the level they already granted' do
        expect(Gitlab::EventStore).not_to receive(:publish_group)

        service.execute([projects[2].id]) { |_| { projects[2].id => 20 } }

        expect(rows_for(user).count { |id, _| id == projects[2].id }).to eq(1)
      end

      it 'keeps the written rows when publishing fails' do
        allow(Gitlab::EventStore).to receive(:publish_group).and_raise(StandardError)

        expect(Gitlab::ErrorTracking).to receive(:track_exception)
        expect(service.execute([projects[3].id]) { |_| { projects[3].id => 30 } })
          .to have_attributes(rows_added: 1)
        expect(rows_for(user)).to include([projects[3].id, 30])
      end

      it 'writes in chunks of at most USER_BATCH_SIZE project IDs, each in its own transaction' do
        stub_const("#{described_class}::USER_BATCH_SIZE", 3)
        stub_const("#{described_class}::BATCH_SIZE", 1)
        chunks = []
        transactions = []

        service.execute(project_ids) do |ids|
          chunks << ids
          transactions << ProjectAuthorization.connection.current_transaction
          {}
        end

        expect(chunks).to eq([project_ids.first(3), project_ids.drop(3)])
        expect(transactions.uniq.size).to eq(2)
      end

      it 'writes nothing for a user that no longer exists' do
        expect(described_class.new(user_id: non_existing_record_id).execute([projects[0].id]) { |_| raise })
          .to have_attributes(rows_added: 0, rows_deleted: 0)
      end
    end

    context 'for one project' do
      subject(:service) { described_class.new(project_id: projects[0].id) }

      it "locks every user in one statement, in user ID order" do
        locks = []
        allow(ProjectAuthorization.connection).to receive(:execute).and_call_original
        allow(ProjectAuthorization.connection).to receive(:execute).with(/pg_advisory_xact_lock/) do |sql|
          locks << sql[/ARRAY\[([\d,]+)\]/, 1].split(',').map(&:to_i)
        end

        service.execute([other_user.id, user.id]) { |ids| ids.index_with(30) }

        expect(locks).to eq([[user.id, other_user.id].sort])
        expect(ProjectAuthorization.where(project: projects[0]).pluck(:user_id))
          .to contain_exactly(user.id, other_user.id)
      end

      it 'changes and removes rows to match the calculation' do
        ProjectAuthorization.insert_all([
          { user_id: user.id, project_id: projects[0].id, access_level: 30, is_unique: true },
          { user_id: other_user.id, project_id: projects[0].id, access_level: 30, is_unique: true }
        ])

        result = service.execute([user.id, other_user.id]) { |_| { user.id => 40 } }

        expect(ProjectAuthorization.where(project: projects[0]).pluck(:user_id, :access_level))
          .to contain_exactly([user.id, 40])
        expect(result).to have_attributes(rows_added: 1, rows_deleted: 2)
      end

      it "doesn't write rows for a user deleted meanwhile" do
        service.execute([non_existing_record_id]) { |ids| ids.index_with(30) }

        expect(ProjectAuthorization.where(project: projects[0])).to be_empty
      end

      it 'writes in chunks of at most BATCH_SIZE IDs, each in its own transaction' do
        stub_const("#{described_class}::BATCH_SIZE", 1)
        chunks = []
        transactions = []
        locked_in = []
        allow(ProjectAuthorization.connection).to receive(:execute).and_call_original
        allow(ProjectAuthorization.connection).to receive(:execute).with(/pg_advisory_xact_lock\(/) do |sql|
          locked_in << ProjectAuthorization.connection.current_transaction
          ProjectAuthorization.connection.exec_query(sql)
        end

        result = service.execute([user.id, other_user.id, user.id]) do |ids|
          chunks << ids
          transactions << ProjectAuthorization.connection.current_transaction
          ids.index_with(30)
        end

        expect(chunks).to eq([[user.id], [other_user.id]])
        expect(transactions.uniq.size).to eq(2)
        expect(locked_in).to eq(transactions)
        expect(result).to have_attributes(rows_added: 2, rows_deleted: 0)
      end
    end

    it 'returns no changes for no IDs' do
      expect(described_class.new(user_id: user.id).execute([]) { |_| raise })
        .to have_attributes(rows_added: 0, rows_deleted: 0)
    end

    it 'needs a block' do
      expect { described_class.new(user_id: user.id).execute([projects[0].id]) }.to raise_error(ArgumentError)
    end

    it 'refuses to run inside a transaction' do
      ProjectAuthorization.transaction do
        expect { described_class.new(user_id: user.id).execute([projects[0].id]) { |_| {} } }
          .to raise_error(RuntimeError, /outside a transaction/)
      end
    end

    it 'runs inside a transaction when the exclusive lease transaction check is skipped' do
      ProjectAuthorization.transaction do
        Gitlab::ExclusiveLease.skipping_transaction_check do
          expect { described_class.new(user_id: user.id).execute([projects[0].id]) { |_| {} } }.not_to raise_error
        end
      end
    end

    it 'ignores the skip outside tests, where after-commit callbacks set it' do
      stub_rails_env('production')

      ProjectAuthorization.transaction do
        Gitlab::ExclusiveLease.skipping_transaction_check do
          expect { described_class.new(user_id: user.id).execute([projects[0].id]) { |_| {} } }
            .to raise_error(RuntimeError, /outside a transaction/)
        end
      end
    end
  end
end
