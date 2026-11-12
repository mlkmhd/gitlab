# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Authz::ProjectAuthorizations::RefreshService, feature_category: :permissions do
  let_it_be(:root) { create(:group) }
  let_it_be(:subgroup) { create(:group, parent: root) }
  let_it_be(:other_root) { create(:group) }
  let_it_be(:project) { create(:project, group: subgroup) }
  let_it_be(:user) { create(:user) }

  let(:runtime_limiter) { Gitlab::Metrics::RuntimeLimiter.new(described_class::LEASE_LIMIT * 4) }
  let(:poll_interval) { nil }
  let(:lease_log_line) do
    hash_including(Labkit::Fields::LOG_MESSAGE => end_with('project authorization refresh events'))
  end

  let(:zero_counts) { %w[project user_in_project user_in_group user].index_with(0) }

  subject(:execute) { described_class.new(runtime_limiter, poll_interval: poll_interval).execute }

  before do
    stub_feature_flags(authz_refresh_compute_projects: false, authz_refresh_compute_memberships: false)
    clear_refresh_queue
  end

  # Fixtures queue events through the refresh triggers, so examples start from an empty queue.
  def clear_refresh_queue
    Authz::ProjectAuthorizations::RefreshEvent.delete_all
  end

  def logged_leases
    leases = []
    allow(Gitlab::AppJsonLogger).to receive(:info).and_call_original
    allow(Gitlab::AppJsonLogger).to receive(:info).with(lease_log_line) { |payload| leases << payload }

    execute

    leases
  end

  # The application context each lease logged in.
  def lease_contexts
    contexts = []
    allow(Gitlab::AppJsonLogger).to receive(:info).and_call_original
    allow(Gitlab::AppJsonLogger).to receive(:info).with(lease_log_line) do
      contexts << Gitlab::ApplicationContext.current
    end

    execute

    contexts
  end

  context 'with events queued' do
    let!(:events) do
      [
        create(:authz_refresh_event, target_type: :project, target_id: project.id),
        create(:authz_refresh_event, target_type: :user_in_group, target_id: user.id, scope_id: root.id),
        create(:authz_refresh_event, target_type: :user_in_group, target_id: user.id, scope_id: subgroup.id),
        create(:authz_refresh_event, target_type: :user, target_id: user.id)
      ]
    end

    it 'drops every event and counts them by target type' do
      expect(execute.payload).to eq(
        drained: true,
        dropped_counts: { 'project' => 1, 'user_in_project' => 0, 'user_in_group' => 2, 'user' => 1 },
        expanded_counts: { 'namespace_subtree' => 0, 'namespace_project_group_links' => 0, 'group_group_link' => 0 },
        finished_counts: zero_counts, continued_counts: zero_counts,
        failed_counts: Authz::ProjectAuthorizations::RefreshEvent.target_types.keys.index_with(0)
      )
      expect(Authz::ProjectAuthorizations::RefreshEvent.where(id: events.map(&:id)).map(&:status))
        .to all(eq('processed'))
    end

    it 'logs each lease with its target and age' do
      events.each { |event| event.update!(first_queued_at: 5.minutes.ago) }

      expect(logged_leases).to contain_exactly(
        hash_including('target_type' => 'project', 'target_id' => project.id, 'scope_id' => nil,
          'events_count' => 1, 'attempts' => 0, 'queued_duration_s' => be_within(60).of(300)),
        hash_including('target_type' => 'user_in_group', 'target_id' => user.id, 'events_count' => 2),
        hash_including('target_type' => 'user', 'target_id' => user.id, 'events_count' => 1)
      )
    end
  end

  context 'with a namespace event queued' do
    let!(:event) { create(:authz_refresh_event, target_type: :namespace_subtree, target_id: subgroup.id) }

    it 'expands it, then drops the events it expanded into' do
      expect(execute.payload).to include(
        drained: true,
        dropped_counts: hash_including('project' => 1),
        expanded_counts: hash_including('namespace_subtree' => 1)
      )
      expect(Authz::ProjectAuthorizations::RefreshEvent.all.map(&:status)).to all(eq('processed'))
    end

    it 'logs how many events it expanded into' do
      expect(logged_leases).to contain_exactly(
        hash_including(Labkit::Fields::LOG_MESSAGE => 'Expanded project authorization refresh events',
          'target_type' => 'namespace_subtree', 'target_id' => subgroup.id, 'events_count' => 1,
          'expanded_events_count' => 1),
        hash_including(Labkit::Fields::LOG_MESSAGE => 'Dropped project authorization refresh events',
          'target_type' => 'project', 'target_id' => project.id)
      )
    end
  end

  context 'when the types compute' do
    let_it_be(:developer) { create(:user) }

    let(:recalculated_log_line) do
      hash_including(Labkit::Fields::LOG_MESSAGE => 'Recalculated project authorization refresh events')
    end

    let(:no_rows) { Authz::ProjectAuthorizations::WriteBatchService::Result.new(0, 0) }
    let(:complete) { ServiceResponse.success(payload: { complete: true, cursor: nil, written: no_rows }) }

    before_all do
      subgroup.add_developer(developer)
    end

    before do
      stub_feature_flags(authz_refresh_compute_projects: true, authz_refresh_compute_memberships: true)
    end

    it 'recalculates a project, finishes its events and logs the rows written' do
      ProjectAuthorization.where(project: project).delete_all
      event = create(:authz_refresh_event, target_type: :project, target_id: project.id)

      expect(logged_leases.sole).to match(recalculated_log_line)
        .and include('complete' => true, 'duration_s' => be >= 0, 'rows_added' => 1, 'rows_deleted' => 0)
      expect(ProjectAuthorization.where(project: project).pluck(:user_id)).to contain_exactly(developer.id)
      expect(event.reload).to be_status_processed
    end

    it 'counts what it finished' do
      create(:authz_refresh_event, target_type: :user_in_group, target_id: developer.id, scope_id: subgroup.id)

      expect(execute.payload).to include(finished_counts: zero_counts.merge('user_in_group' => 1),
        dropped_counts: zero_counts)
    end

    it 'recalculates the projects a namespace event expands into' do
      create(:authz_refresh_event, target_type: :namespace_subtree, target_id: subgroup.id)

      expect(execute.payload).to include(finished_counts: zero_counts.merge('project' => 1),
        expanded_counts: hash_including('namespace_subtree' => 1))
    end

    describe 'dispatch' do
      using RSpec::Parameterized::TableSyntax

      let(:limiter) { an_instance_of(Gitlab::Metrics::RuntimeLimiter) }
      let(:user_in_project_arguments) { { project_ids: [7] } }
      let(:user_in_group_arguments) { { group_ids: [8, 9], cursor: 3, runtime_limiter: limiter } }
      let(:user_arguments) { { cursor: 3, runtime_limiter: limiter } }

      it 'recalculates a project with a runtime limit' do
        create(:authz_refresh_event, target_type: :project, target_id: project.id)

        expect(Authz::ProjectAuthorizations::RecalculateProjectService).to receive(:new)
          .with(project.id, runtime_limiter: limiter).and_return(instance_double(
            Authz::ProjectAuthorizations::RecalculateProjectService, execute: complete))

        execute
      end

      # The two user_in_group events merge into one lease.
      where(:target_type, :scope_ids, :cursor, :arguments) do
        :user_in_project | [7]    | nil | ref(:user_in_project_arguments)
        :user_in_group   | [8, 9] | 3   | ref(:user_in_group_arguments)
        :user            | [nil]  | 3   | ref(:user_arguments)
      end

      with_them do
        it "recalculates the user with the lease's projects, groups and cursor" do
          scope_ids.each do |scope_id|
            create(:authz_refresh_event, target_type: target_type, target_id: developer.id, scope_id: scope_id,
              cursor: cursor)
          end

          expect(Authz::ProjectAuthorizations::RecalculateUserService).to receive(:new)
            .with(developer.id, **arguments).and_return(instance_double(
              Authz::ProjectAuthorizations::RecalculateUserService, execute: complete))

          execute
        end
      end
    end

    it 'continues from the cursor when the recalculation runs out of time, keeping the age' do
      create(:authz_refresh_event, target_type: :user, target_id: developer.id, first_queued_at: 5.minutes.ago)
      stopped = ServiceResponse.success(payload: { complete: false, cursor: 42, written: no_rows })

      expect(Authz::ProjectAuthorizations::RecalculateUserService).to receive(:new)
        .with(developer.id, cursor: nil, runtime_limiter: anything).ordered
        .and_return(instance_double(Authz::ProjectAuthorizations::RecalculateUserService, execute: stopped))
      expect(Authz::ProjectAuthorizations::RecalculateUserService).to receive(:new)
        .with(developer.id, cursor: 42, runtime_limiter: anything).ordered
        .and_return(instance_double(Authz::ProjectAuthorizations::RecalculateUserService, execute: complete))

      leases = logged_leases

      expect(leases.pluck('complete')).to eq([false, true])
      expect(leases.last['queued_duration_s']).to be_within(60).of(300)
    end

    it 'drops the events of a project the flag is off for, including its users' do
      stub_feature_flags(authz_refresh_compute_projects: create(:project))
      clear_refresh_queue
      create(:authz_refresh_event, target_type: :project, target_id: project.id)
      create(:authz_refresh_event, target_type: :user_in_project, target_id: developer.id, scope_id: project.id)

      expect(Authz::ProjectAuthorizations::RecalculateProjectService).not_to receive(:new)
      expect(Authz::ProjectAuthorizations::RecalculateUserService).not_to receive(:new)

      expect(execute.payload).to include(dropped_counts: zero_counts.merge('project' => 1, 'user_in_project' => 1))
    end

    it 'retries the events later when the recalculation fails' do
      create(:authz_refresh_event, target_type: :project, target_id: project.id)
      allow_next_instance_of(Authz::ProjectAuthorizations::RecalculateProjectService) do |service|
        allow(service).to receive(:execute).and_raise(ActiveRecord::QueryCanceled)
      end

      expect(Gitlab::ErrorTracking).to receive(:track_exception)
        .with(instance_of(ActiveRecord::QueryCanceled), hash_including(target_type: :project))

      expect(execute.payload).to include(failed_counts: hash_including('project' => 1))
      expect(Authz::ProjectAuthorizations::RefreshEvent.status_pending.sole).to have_attributes(attempts: 1)
    end

    it 'fails the events of a computed type that has no recalculation' do
      stub_const('Authz::ProjectAuthorizations::RefreshEvent::EXPANSION_TYPES', [])
      allow(Authz::ProjectAuthorizations::RefreshEvent).to receive(:computed?).and_return(true)
      create(:authz_refresh_event, target_type: :namespace_subtree, target_id: subgroup.id)

      expect(Gitlab::ErrorTracking).to receive(:track_exception)
        .with(instance_of(ArgumentError), hash_including(target_type: :namespace_subtree))

      expect(execute.payload).to include(failed_counts: hash_including('namespace_subtree' => 1))
    end

    it 'leaves the events to the worker that took them over when the lease expired during the recalculation' do
      event = create(:authz_refresh_event, target_type: :user, target_id: developer.id)
      allow_next_instance_of(Authz::ProjectAuthorizations::RecalculateUserService) do |service|
        allow(service).to receive(:execute) do
          Authz::ProjectAuthorizations::RefreshEvent.where(id: event.id).update_all(
            status: Authz::ProjectAuthorizations::RefreshEvent.statuses[:processed])
          complete
        end
      end

      expect(execute.payload).to include(finished_counts: zero_counts, failed_counts: hash_including('user' => 0))
      expect(Authz::ProjectAuthorizations::RefreshEvent.status_pending).to be_empty
    end
  end

  describe 'context attribution' do
    using RSpec::Parameterized::TableSyntax

    where(:target_type, :target, :scope, :expected_root, :expects_user) do
      :project                       | :project  | nil         | :root | false
      :user_in_project               | :user     | :project    | :root | true
      :user_in_group                 | :user     | :subgroup   | :root | true
      :namespace_subtree             | :subgroup | nil         | :root | false
      :namespace_project_group_links | :subgroup | nil         | :root | false
      :group_group_link              | :subgroup | :root       | :root | false
      :group_group_link              | :subgroup | :other_root | nil   | false
      :user                          | :user     | nil         | nil   | true
    end

    with_them do
      before do
        create(:authz_refresh_event, target_type: target_type, target_id: public_send(target).id,
          scope_id: scope && public_send(scope).id)
        # Expanded events would lease after this one.
        allow(Authz::ProjectAuthorizations::RefreshEvent).to receive(:enqueue)
      end

      it 'sets the root namespace and user only when the work unambiguously belongs to them' do
        context = lease_contexts.sole

        expect(context['meta.root_namespace']).to eq(expected_root && public_send(expected_root).full_path)
        expect(context['meta.user']).to eq(expects_user ? user.username : nil)
      end
    end

    it 'sets no root namespace for a user_in_group lease across several roots' do
      create(:authz_refresh_event, target_type: :user_in_group, target_id: user.id, scope_id: subgroup.id)
      create(:authz_refresh_event, target_type: :user_in_group, target_id: user.id, scope_id: other_root.id)

      expect(lease_contexts.sole).to include('meta.user' => user.username).and exclude('meta.root_namespace')
    end

    it 'sets no user for a deleted user' do
      create(:authz_refresh_event, target_type: :user, target_id: non_existing_record_id)

      expect(lease_contexts.sole).not_to include('meta.user')
    end

    it 'logs the root namespace ID' do
      create(:authz_refresh_event, target_type: :project, target_id: project.id)

      expect(lease_contexts.sole).to include('meta.gl_root_namespace_id' => root.id)
    end

    it 'drops the lease without a context when finding one fails' do
      event = create(:authz_refresh_event, target_type: :project, target_id: project.id)
      allow(Namespace).to receive(:root_ids_for).and_raise(ActiveRecord::QueryCanceled)

      expect(Gitlab::ErrorTracking).to receive(:track_exception)
        .with(instance_of(ActiveRecord::QueryCanceled), hash_including(target_type: :project))

      expect(lease_contexts.sole).not_to include('meta.root_namespace')
      expect(event.reload).to be_status_processed
    end

    it 'sets no context for a deleted project' do
      create(:authz_refresh_event, target_type: :project, target_id: non_existing_record_id)

      expect(lease_contexts.sole).not_to include('meta.root_namespace', 'meta.user')
    end

    it 'reports a failed lease with its context' do
      create(:authz_refresh_event, target_type: :project, target_id: project.id)
      calls = 0
      allow(Authz::ProjectAuthorizations::RefreshEvent).to receive(:finish).and_wrap_original do |original, lease|
        calls += 1
        raise ActiveRecord::QueryCanceled if calls == 1

        original.call(lease)
      end

      expect(Gitlab::ErrorTracking).to receive(:track_exception) do
        expect(Gitlab::ApplicationContext.current).to include('meta.root_namespace' => root.full_path)
      end

      execute
    end
  end

  context 'when too little runtime is left for a lease' do
    let(:runtime_limiter) { Gitlab::Metrics::RuntimeLimiter.new(described_class::LEASE_LIMIT - 1.second) }

    it 'leases nothing' do
      event = create(:authz_refresh_event)

      expect(execute.payload).to include(drained: false)
      expect(event.reload).to have_attributes(status: 'pending', visible_at: nil)
    end
  end

  context 'with a poll interval' do
    let(:poll_interval) { 1.second }

    it 'waits on an empty queue and leases what arrives, until the runtime runs out' do
      service = described_class.new(runtime_limiter, poll_interval: poll_interval)
      sleeps = 0

      allow(service).to receive(:sleep).with(poll_interval) do
        sleeps += 1
        create(:authz_refresh_event) if sleeps == 1
        allow(runtime_limiter).to receive(:elapsed_time).and_return(runtime_limiter.max_runtime) if sleeps == 2
      end

      expect(service.execute.payload).to include(drained: false, dropped_counts: hash_including('project' => 1))
      expect(sleeps).to eq(2)
    end
  end

  context 'when processing a lease fails' do
    let!(:event) { create(:authz_refresh_event) }

    before do
      # Only the first: `fail` finishes the leased events after inserting their retry.
      calls = 0
      allow(Authz::ProjectAuthorizations::RefreshEvent).to receive(:finish).and_wrap_original do |original, lease|
        calls += 1
        raise ActiveRecord::QueryCanceled if calls == 1

        original.call(lease)
      end
    end

    it 'retries the events later and tracks the error' do
      expect(Gitlab::ErrorTracking).to receive(:track_exception)
        .with(instance_of(ActiveRecord::QueryCanceled), hash_including(target_type: :project, attempts: 0))

      expect(execute.payload).to include(drained: true, dropped_counts: hash_including('project' => 0),
        failed_counts: hash_including('project' => 1))
      expect(Authz::ProjectAuthorizations::RefreshEvent.status_pending.sole)
        .to have_attributes(target_id: event.target_id, attempts: 1)
    end
  end

  context 'when an expansion fails partway' do
    let_it_be(:other_project) { create(:project, group: subgroup) }
    let!(:event) { create(:authz_refresh_event, target_type: :namespace_subtree, target_id: subgroup.id) }

    before do
      stub_const("#{Authz::ProjectAuthorizations::ExpandService}::BATCH_SIZE", 1)
      calls = 0
      allow(Authz::ProjectAuthorizations::RefreshEvent).to receive(:enqueue)
        .and_wrap_original do |original, *args, **opts|
        calls += 1
        raise ActiveRecord::QueryCanceled if calls == 2

        original.call(*args, **opts)
      end
    end

    it 'retries it from after the batches it queued' do
      execute

      expect(Authz::ProjectAuthorizations::RefreshEvent.status_pending.sole).to have_attributes(
        target_type: 'namespace_subtree', attempts: 1, cursor: [project.id, other_project.id].min)
    end
  end

  context 'when another worker took an expired lease over and finished it first' do
    let!(:event) { create(:authz_refresh_event, target_type: :namespace_subtree, target_id: subgroup.id) }

    before do
      allow(Authz::ProjectAuthorizations::RefreshEvent).to receive(:lease).and_wrap_original do |original, **args|
        original.call(**args).tap do |lease|
          # The other worker, between this lease and its finish.
          event.update!(status: :processed) if lease&.event_ids == [event.id]
        end
      end
    end

    it 'logs the lost lease and moves on, without retrying it or queueing its expansion' do
      allow(Gitlab::AppJsonLogger).to receive(:info).and_call_original
      expect(Gitlab::AppJsonLogger).to receive(:info)
        .with(hash_including(Labkit::Fields::LOG_MESSAGE => 'Lost project authorization refresh lease',
          'target_type' => 'namespace_subtree', 'target_id' => subgroup.id))
      expect(Gitlab::ErrorTracking).not_to receive(:track_exception)

      expect(execute.payload).to include(drained: true, expanded_counts: hash_including('namespace_subtree' => 0))
      expect(Authz::ProjectAuthorizations::RefreshEvent.status_pending).to be_empty
    end
  end

  context 'when a lease fails after another worker took it over' do
    let!(:event) { create(:authz_refresh_event, target_type: :namespace_subtree, target_id: subgroup.id) }

    before do
      allow_next_instance_of(Authz::ProjectAuthorizations::ExpandService) do |service|
        allow(service).to receive(:execute) do
          event.update!(status: :processed)
          raise ActiveRecord::QueryCanceled
        end
      end
    end

    it 'tracks the error and logs the lost lease, without queueing a retry' do
      allow(Gitlab::AppJsonLogger).to receive(:info).and_call_original
      expect(Gitlab::AppJsonLogger).to receive(:info)
        .with(hash_including(Labkit::Fields::LOG_MESSAGE => 'Lost project authorization refresh lease'))
      expect(Gitlab::ErrorTracking).to receive(:track_exception)
        .with(instance_of(ActiveRecord::QueryCanceled), anything)

      execute

      expect(Authz::ProjectAuthorizations::RefreshEvent.status_pending).to be_empty
    end
  end

  context 'when Sidekiq stops mid-lease' do
    let!(:event) { create(:authz_refresh_event) }

    before do
      allow(Authz::ProjectAuthorizations::RefreshEvent).to receive(:finish).and_raise(Sidekiq::Shutdown)
    end

    it 'releases the events straight away and stops' do
      expect { execute }.to raise_error(Sidekiq::Shutdown)

      expect(event.reload).to have_attributes(status: 'pending', visible_at: be <= Time.current)
    end
  end
end
