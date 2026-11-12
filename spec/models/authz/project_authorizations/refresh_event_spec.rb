# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Authz::ProjectAuthorizations::RefreshEvent, feature_category: :permissions do
  # created_at is passed because the database's now() doesn't follow time travel.
  def insert_event(target_type, scope_id: nil)
    described_class.connection.select_value(described_class.sanitize_sql_array([
      'INSERT INTO authz_refresh_events (target_type, target_id, scope_id, created_at) VALUES (?, 1, ?, ?) ' \
        'RETURNING partition',
      described_class.target_types.fetch(target_type), scope_id, Time.current
    ]))
  end

  def partition_values
    described_class.partitioning_strategy.current_partitions.map(&:value)
  end

  it 'keeps the target type values the trigger functions write' do
    expect(described_class.target_types).to eq(
      'project' => 1, 'user_in_project' => 2, 'user_in_group' => 3, 'user' => 4, 'namespace_subtree' => 5,
      'namespace_project_group_links' => 6, 'group_group_link' => 7
    )
  end

  it 'defaults to a pending event with no attempts, first queued and created now' do
    event = create(:authz_refresh_event)

    expect(event.reload).to have_attributes(status: 'pending', attempts: 0, cursor: nil, visible_at: nil,
      created_at: be_within(1.minute).of(Time.current), first_queued_at: be_within(1.minute).of(Time.current))
  end

  describe 'sliding list partitioning' do
    let(:active_partition) { described_class.partitioning_strategy.active_partition }

    describe 'next_partition_if' do
      subject(:next_partition) { described_class.partitioning_strategy.next_partition_if.call(active_partition) }

      it { is_expected.to be(false) }

      it 'stays on the partition while its oldest event is recent' do
        create(:authz_refresh_event, created_at: 1.hour.ago)

        expect(next_partition).to be(false)
      end

      it 'moves to a new partition once its oldest event is older than a day' do
        create(:authz_refresh_event, created_at: (described_class::PARTITION_DURATION + 1.hour).ago)
        create(:authz_refresh_event)

        expect(next_partition).to be(true)
      end

      it 'ignores how long ago a carried-over event was first queued' do
        create(:authz_refresh_event, first_queued_at: 3.days.ago)

        expect(next_partition).to be(false)
      end
    end

    describe 'detach_partition_if' do
      subject(:detach) { described_class.partitioning_strategy.detach_partition_if.call(active_partition) }

      it 'keeps a partition with a pending event' do
        create(:authz_refresh_event, status: :processed)
        create(:authz_refresh_event)

        expect(detach).to be(false)
      end

      it 'detaches a partition whose events are all processed' do
        create(:authz_refresh_event, status: :processed)

        expect(detach).to be(true)
      end
    end

    describe 'with the partition manager', :freeze_time do
      let(:partition_manager) { Gitlab::Database::Partitioning::PartitionManager.new(described_class) }

      it 'writes new events to a new partition after a day and drops the old one once processed' do
        expect(partition_values).to eq([1])
        expect(insert_event(:project)).to eq(1)

        partition_manager.sync_partitions
        expect(partition_values).to eq([1])

        travel(described_class::PARTITION_DURATION + 1.second)
        partition_manager.sync_partitions

        expect(partition_values).to contain_exactly(1, 2)
        expect(insert_event(:project)).to eq(2)

        described_class.for_partition(1).update_all(status: described_class.statuses[:processed])
        partition_manager.sync_partitions

        expect(partition_values).to eq([2])
        expect(described_class.count).to eq(1)
      end

      it 'keeps the old partition while one of its events is still pending' do
        insert_event(:project)

        travel(described_class::PARTITION_DURATION + 1.second)
        partition_manager.sync_partitions
        partition_manager.sync_partitions

        expect(partition_values).to contain_exactly(1, 2)
      end
    end
  end

  describe 'scope_id check constraint' do
    pair_types = %w[user_in_project user_in_group group_group_link]

    described_class.target_types.each_key do |target_type|
      context "for #{target_type} events" do
        if pair_types.include?(target_type)
          it 'requires a scope' do
            expect { insert_event(target_type, scope_id: 1) }.to change { described_class.count }.by(1)
            expect { insert_event(target_type) }
              .to raise_error(ActiveRecord::StatementInvalid, /check_authz_refresh_events_scope_id/)
          end
        else
          it 'rejects a scope' do
            expect { insert_event(target_type) }.to change { described_class.count }.by(1)
            expect { insert_event(target_type, scope_id: 1) }
              .to raise_error(ActiveRecord::StatementInvalid, /check_authz_refresh_events_scope_id/)
          end
        end
      end
    end
  end

  it { is_expected.to validate_presence_of(:target_type) }
  it { is_expected.to validate_presence_of(:target_id) }

  def events
    described_class.order(:id).map { |event| [event.target_type.to_sym, event.target_id, event.scope_id] }
  end

  # New events go to partition 2 from here on, as after the partition manager moves forward.
  def start_partition_2
    described_class.connection.execute(
      'CREATE TABLE gitlab_partitions_dynamic.authz_refresh_events_2 PARTITION OF authz_refresh_events ' \
        'FOR VALUES IN (2)'
    )
    described_class.connection.execute('ALTER TABLE authz_refresh_events ALTER COLUMN partition SET DEFAULT 2')
  end

  describe '.computed?' do
    let_it_be(:project) { create(:project) }
    let_it_be(:other_project) { create(:project) }
    let_it_be(:user) { create(:user) }
    let_it_be(:other_user) { create(:user) }

    before do
      stub_feature_flags(authz_refresh_write_path: true, authz_project_refresh_write_path: true,
        authz_refresh_compute_projects: project, authz_refresh_compute_memberships: user)
    end

    it 'checks project types per project' do
      expect(described_class.computed?(:project, project.id)).to be(true)
      expect(described_class.computed?(:user_in_project, project.id)).to be(true)
      expect(described_class.computed?(:project, other_project.id)).to be(false)
    end

    it 'is not true for every project until the projects flag is fully on' do
      expect(described_class.computed?(:project)).to be(false)

      stub_feature_flags(authz_refresh_compute_projects: true)

      expect(described_class.computed?(:project)).to be(true)
    end

    it 'computes membership types only once projects compute for every project, then per user' do
      expect(described_class.computed?(:user_in_group, user.id)).to be(false)

      stub_feature_flags(authz_refresh_compute_projects: true)

      expect(described_class.computed?(:user_in_group, user.id)).to be(true)
      expect(described_class.computed?(:user, user.id)).to be(true)
      expect(described_class.computed?(:user, other_user.id)).to be(false)
    end

    it 'computes nothing until the write path is on for every user' do
      stub_feature_flags(authz_refresh_write_path: user, authz_refresh_compute_projects: true)

      expect(described_class.computed?(:project, project.id)).to be(false)
      expect(described_class.computed?(:user, user.id)).to be(false)
    end

    it 'computes nothing until the project write path is on for every project' do
      stub_feature_flags(authz_project_refresh_write_path: project, authz_refresh_compute_projects: true,
        authz_refresh_compute_memberships: true)

      expect(described_class.computed?(:project, project.id)).to be(false)
      expect(described_class.computed?(:user, user.id)).to be(false)
    end
  end

  describe 'Lease#actor_id' do
    it "is the project for a user's project event, and the target otherwise" do
      create(:authz_refresh_event, target_type: :user_in_project, target_id: 1, scope_id: 2)
      create(:authz_refresh_event, target_type: :user_in_group, target_id: 3, scope_id: 4)

      expect(described_class.lease(duration: 1.minute).actor_id).to eq(2)
      expect(described_class.lease(duration: 1.minute).actor_id).to eq(3)
    end
  end

  describe '.lease' do
    let(:lease) { described_class.lease(duration: 4.minutes) }

    it 'returns nil when nothing is ready' do
      create(:authz_refresh_event, visible_at: 1.minute.from_now)

      expect(lease).to be_nil
    end

    it "merges a user's ready and debounced membership events across groups, and hides them" do
      first = create(:authz_refresh_event, target_type: :user_in_group, target_id: 1, scope_id: 2)
      debounced = create(:authz_refresh_event, target_type: :user_in_group, target_id: 1, scope_id: 3,
        visible_at: 5.seconds.from_now)
      other_user = create(:authz_refresh_event, target_type: :user_in_group, target_id: 9, scope_id: 2)

      expect(lease).to have_attributes(event_ids: contain_exactly(first.id, debounced.id), target_type: :user_in_group,
        target_id: 1, group_ids: [2, 3], cursor: nil)
      expect(first.reload.visible_at).to be > 3.minutes.from_now
      expect(other_user.reload.visible_at).to be_nil
    end

    it 'merges other types only for the same scope' do
      create(:authz_refresh_event, target_type: :user_in_project, target_id: 1, scope_id: 2)
      create(:authz_refresh_event, target_type: :user_in_project, target_id: 1, scope_id: 3)

      expect(lease).to have_attributes(group_ids: [2], scope_id: 2)
    end

    it 'merges only events with the same attempts and cursor as the head' do
      head = create(:authz_refresh_event, target_type: :user_in_group, target_id: 1, scope_id: 2, attempts: 1)
      create(:authz_refresh_event, target_type: :user_in_group, target_id: 1, scope_id: 3)
      create(:authz_refresh_event, target_type: :user_in_group, target_id: 1, scope_id: 4, attempts: 1, cursor: 50)

      expect(lease.event_ids).to eq([head.id])
    end

    it "isn't answered from the query cache, which Sidekiq jobs run with" do
      create(:authz_refresh_event, target_id: 1)

      ApplicationRecord.cache do
        expect(described_class.lease(duration: 4.minutes)).to be_present
        expect(described_class.lease(duration: 4.minutes)).to be_nil
      end
    end

    it 'never leases or merges processed events' do
      create(:authz_refresh_event, target_id: 1, status: :processed)
      pending = create(:authz_refresh_event, target_id: 1)
      create(:authz_refresh_event, target_id: 1, status: :processed)

      expect(lease.event_ids).to eq([pending.id])
    end

    it 'skips events another lease holds' do
      create(:authz_refresh_event, target_id: 1, visible_at: 2.minutes.from_now)
      ready = create(:authz_refresh_event, target_id: 2)

      expect(lease.event_ids).to eq([ready.id])
    end

    it "doesn't merge events another lease holds" do
      ready = create(:authz_refresh_event, target_id: 1)
      create(:authz_refresh_event, target_id: 1, visible_at: 2.minutes.from_now)

      expect(lease.event_ids).to eq([ready.id])
    end

    it 'merges at most MERGE_LIMIT events with the head, in scope order' do
      stub_const("#{described_class}::MERGE_LIMIT", 2)
      [9, 2, 3, 4].each do |group_id|
        create(:authz_refresh_event, target_type: :user_in_group, target_id: 1, scope_id: group_id)
      end

      expect(lease.group_ids).to eq([2, 3, 9])
    end

    it 'merges a scoped type only on the same scope, however many events the target has' do
      stub_const("#{described_class}::MERGE_LIMIT", 2)
      head = create(:authz_refresh_event, target_type: :user_in_project, target_id: 1, scope_id: 5)
      create_list(:authz_refresh_event, 3, target_type: :user_in_project, target_id: 1, scope_id: 6)
      same = create(:authz_refresh_event, target_type: :user_in_project, target_id: 1, scope_id: 5)

      expect(lease.event_ids).to contain_exactly(head.id, same.id)
    end

    it 'leases events again once their lease runs out' do
      expired = create(:authz_refresh_event, visible_at: 1.second.ago)

      expect(lease.event_ids).to eq([expired.id])
    end

    it 'merges events across partitions and returns their partitions' do
      old = create(:authz_refresh_event, target_id: 1)
      start_partition_2
      new = create(:authz_refresh_event, target_id: 1)

      expect(lease.event_ids_by_partition).to eq(1 => [old.id], 2 => [new.id])
    end
  end

  describe 'after a lease' do
    let!(:events_for_target) do
      [create(:authz_refresh_event, target_id: 1, attempts: 2, first_queued_at: 1.hour.ago, cursor: 10),
        create(:authz_refresh_event, target_id: 1, attempts: 2, cursor: 10)]
    end

    let(:lease) { described_class.lease(duration: 4.minutes) }

    it '.finish marks the leased events processed only' do
      lease
      later = create(:authz_refresh_event, target_id: 1)

      described_class.finish(lease)

      expect(described_class.status_pending).to contain_exactly(later)
      expect(events_for_target.map(&:reload)).to all(be_status_processed)
    end

    it '.finish raises when another worker took the expired lease over and finished it first' do
      described_class.finish(lease)

      expect { described_class.finish(lease) }.to raise_error(described_class::LeaseLostError)
    end

    it '.continue queues nothing when another worker took the expired lease over and finished it first' do
      described_class.finish(lease)

      expect { described_class.continue(lease, cursor: 40) }.to raise_error(described_class::LeaseLostError)
      expect(described_class.status_pending).to be_empty
    end

    describe '.advance' do
      it 'moves their cursor and returns the lease at it' do
        expect(described_class.advance(lease, cursor: 40)).to eq(lease.with(cursor: 40))
        expect(events_for_target.map { |event| event.reload.cursor }).to all(eq(40))
      end

      it 'raises when another worker holding the same expired lease advanced it first' do
        described_class.advance(lease, cursor: 40)

        expect { described_class.advance(lease, cursor: 50) }.to raise_error(described_class::LeaseLostError)
        expect(events_for_target.map { |event| event.reload.cursor }).to all(eq(40))
      end

      it 'raises when another worker finished them first' do
        described_class.finish(lease)

        expect { described_class.advance(lease, cursor: 40) }.to raise_error(described_class::LeaseLostError)
      end
    end

    it '.release makes them ready again' do
      described_class.release(lease)

      expect(described_class.lease(duration: 4.minutes).event_ids).to match_array(lease.event_ids)
    end

    describe '.fail' do
      it 'replaces them with one event with one more attempt, backed off, keeping their age and cursor' do
        described_class.fail(lease)

        expect(events_for_target.map(&:reload)).to all(be_status_processed)
        expect(described_class.status_pending).to contain_exactly(
          have_attributes(target_type: 'project', target_id: 1, attempts: 3, cursor: 10,
            visible_at: be > 3.minutes.from_now,
            first_queued_at: be_within(1.second).of(events_for_target.first.first_queued_at))
        )
      end

      it 'resumes from a cursor the lease advanced' do
        described_class.advance(lease, cursor: 40)

        described_class.fail(lease)

        expect(described_class.status_pending).to contain_exactly(have_attributes(attempts: 3, cursor: 40))
      end

      it 'writes the new event to the active partition' do
        start_partition_2

        described_class.fail(lease)

        expect(described_class.status_pending.pluck(:partition)).to eq([2])
        expect(described_class.for_partition(1).status_pending).to be_empty
      end

      it 'caps the backoff at MAX_BACKOFF' do
        described_class.delete_all
        create(:authz_refresh_event, target_id: 1, attempts: 10)

        described_class.fail(described_class.lease(duration: 4.minutes))

        expect(described_class.status_pending.pick(:visible_at))
          .to be_within(1.minute).of(described_class::MAX_BACKOFF.from_now)
      end

      it 'keeps the leased events when the replacement fails' do
        allow(described_class).to receive(:finish).and_raise(ActiveRecord::StatementInvalid)

        expect { described_class.fail(lease) }.to raise_error(ActiveRecord::StatementInvalid)
        expect(described_class.status_pending).to match_array(events_for_target)
      end
    end

    it '.continue replaces them with one event that keeps their age, attempts and the cursor' do
      described_class.continue(lease, cursor: 40)

      expect(described_class.status_pending).to contain_exactly(
        have_attributes(target_type: 'project', target_id: 1, attempts: 2, cursor: 40,
          first_queued_at: be_within(1.second).of(events_for_target.first.first_queued_at))
      )
    end

    it '.continue writes one event per merged group' do
      described_class.delete_all
      create(:authz_refresh_event, target_type: :user_in_group, target_id: 1, scope_id: 2)
      create(:authz_refresh_event, target_type: :user_in_group, target_id: 1, scope_id: 3)

      described_class.continue(described_class.lease(duration: 4.minutes), cursor: 7)

      expect(described_class.status_pending.pluck(:target_id, :scope_id, :cursor))
        .to contain_exactly([1, 2, 7], [1, 3, 7])
    end
  end

  describe 'writes after a lease that spans partitions' do
    let!(:old) { create(:authz_refresh_event, target_id: 1) }
    let!(:new) do
      start_partition_2
      create(:authz_refresh_event, target_id: 1)
    end

    let(:lease) { described_class.lease(duration: 4.minutes) }

    def update_sql
      lease
      ActiveRecord::QueryRecorder.new { yield }.log.grep(/\bUPDATE\b/)
    end

    %i[finish release fail].each do |method|
      it ".#{method} filters each statement by partition", :aggregate_failures do
        statements = update_sql { described_class.public_send(method, lease) }

        expect(statements.size).to eq(2)
        expect(statements).to all(match(/"?partition"? = /))
      end
    end

    it '.advance filters each statement by partition' do
      statements = update_sql { described_class.advance(lease, cursor: 1) }

      expect(statements.size).to eq(2)
      expect(statements).to all(match(/"?partition"? = /))
    end

    it '.finish marks the events in both partitions processed' do
      described_class.finish(lease)

      expect([old, new].map(&:reload)).to all(be_status_processed)
    end
  end

  describe '.enqueue' do
    it 'inserts one event per target' do
      described_class.enqueue(:user_in_group, [[1, 2], [3, 4]])
      described_class.enqueue(:project, [5])

      expect(events).to eq([[:user_in_group, 1, 2], [:user_in_group, 3, 4], [:project, 5, nil]])
    end

    it 'carries over when the change was first queued' do
      described_class.enqueue(:project, [5], first_queued_at: 1.hour.ago)
      described_class.enqueue(:project, [6])

      expect(described_class.order(:id)).to match([
        have_attributes(first_queued_at: be_within(1.second).of(1.hour.ago),
          created_at: be_within(1.minute).of(Time.current)),
        have_attributes(first_queued_at: be_within(1.minute).of(Time.current))
      ])
    end
  end

  describe '.pending_for?' do
    using RSpec::Parameterized::TableSyntax

    let(:pending) { described_class.pending_for?(user_id: 1, project_id: 2, namespace_ids: [3, 4]) }

    where(:target_type, :target_id, :scope_id, :result) do
      :user_in_group                 | 1 | 5   | true
      :user                          | 1 | nil | true
      :user_in_project               | 1 | 2   | true
      :user_in_project               | 1 | 9   | false
      :project                       | 2 | nil | true
      :project                       | 9 | nil | false
      :namespace_subtree             | 4 | nil | true
      :namespace_project_group_links | 3 | nil | true
      :namespace_subtree             | 9 | nil | false
      # A group_group_link event is found by the shared group, its scope, not by the invited group, its target.
      :group_group_link              | 9 | 4   | true
      :group_group_link              | 4 | 9   | false
    end

    with_them do
      it 'finds only events that can change the pair' do
        create(:authz_refresh_event, target_type: target_type, target_id: target_id, scope_id: scope_id)

        expect(pending).to be(result)
      end
    end

    it 'ignores processed events' do
      create(:authz_refresh_event, target_type: :user, target_id: 1, status: :processed)

      expect(pending).to be(false)
    end

    it 'ignores poison events' do
      create(:authz_refresh_event, target_type: :user, target_id: 1, attempts: described_class::POISON_ATTEMPTS)

      expect(pending).to be(false)
    end
  end

  describe '.expansion_pending?' do
    it 'is true for a pending namespace or share change event' do
      create(:authz_refresh_event, target_type: :namespace_project_group_links, target_id: 1)

      expect(described_class.expansion_pending?).to be(true)
    end

    it 'ignores other types, processed events and poison events' do
      create(:authz_refresh_event, target_type: :project, target_id: 1)
      create(:authz_refresh_event, target_type: :namespace_subtree, target_id: 1, status: :processed)
      create(:authz_refresh_event, target_type: :namespace_subtree, target_id: 2,
        attempts: described_class::POISON_ATTEMPTS)

      expect(described_class.expansion_pending?).to be(false)
    end
  end
end
