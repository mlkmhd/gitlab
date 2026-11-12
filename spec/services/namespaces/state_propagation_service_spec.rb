# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Namespaces::StatePropagationService, feature_category: :groups_and_projects do
  let_it_be_with_reload(:root_group) { create(:group) }
  let_it_be_with_reload(:subgroup) { create(:group, parent: root_group) }
  let_it_be_with_reload(:leaf_group) { create(:group, parent: subgroup) }

  subject(:service) { described_class.new(root_group.id) }

  shared_examples 'does not log propagation start or completion' do
    it 'does not log propagation start or completion' do
      allow(Gitlab::AppLogger).to receive(:info).and_call_original
      expect(Gitlab::AppLogger).not_to receive(:info)
        .with(hash_including(Labkit::Fields::LOG_MESSAGE => a_string_starting_with('Namespace state propagation')))

      service.execute
    end
  end

  describe '#execute' do
    let!(:propagation) do
      create(:namespace_state_propagation, :ancestor_inherited_to_archived, namespace: root_group)
    end

    it 'marks the outbox record as processing before propagating' do
      statuses = []

      allow(Namespace).to receive(:overwrite_state_in_batch).and_wrap_original do |method, *args, **kwargs|
        statuses << propagation.reload.status
        method.call(*args, **kwargs)
      end

      service.execute

      expect(statuses).to eq(['processing'])
    end

    it 'propagates the target state to overwritable descendants', :aggregate_failures do
      service.execute

      expect(subgroup.reload.state).to eq('archived')
      expect(leaf_group.reload.state).to eq('archived')
    end

    it 'refreshes started_at after each propagated batch' do
      stub_const("#{described_class}::STATE_PROPAGATION_ITERATOR_BATCH_SIZE", 1)
      heartbeats = []

      allow(Namespace).to receive(:overwrite_state_in_batch).and_wrap_original do |method, *args, **kwargs|
        heartbeats << propagation.reload.started_at
        travel 1.minute
        method.call(*args, **kwargs)
      end

      service.execute

      expect(heartbeats.size).to be > 1
      expect(heartbeats).to eq(heartbeats.sort.uniq)
    end

    context 'when the runtime limit is exceeded by the last record' do
      before do
        stub_const("#{described_class}::MAX_RUNTIME", 0)
      end

      it 'applies the record without re-enqueuing the namespace', :aggregate_failures do
        expect(Namespaces::StatePropagationWorker).not_to receive(:perform_async)

        service.execute

        expect(subgroup.reload.state).to eq('archived')
        expect(Namespaces::StatePropagation.exists?(propagation.id)).to be(false)
      end
    end

    it 'deletes the outbox record on completion' do
      service.execute

      expect(Namespaces::StatePropagation.exists?(propagation.id)).to be(false)
    end

    it 'observes the propagation duration once' do
      expect(Gitlab::NamespaceStatePropagation::Metrics)
        .to receive(:observe_duration).once.with('archived', a_kind_of(Numeric))

      service.execute
    end

    it 'excludes the claim from the observed duration' do
      clock = 0.0
      allow(::Gitlab::Metrics::System).to receive(:monotonic_time) { clock }
      allow(Namespaces::StatePropagation).to receive(:next_for).and_return(propagation, nil)
      allow(propagation).to receive(:claim).and_wrap_original do |method|
        clock += 100
        method.call
      end

      expect(Gitlab::NamespaceStatePropagation::Metrics).to receive(:observe_duration).with('archived', 0.0)

      service.execute
    end

    it 'increments the boundary rewinds counter when a descendant becomes a boundary mid-walk' do
      create(:group, parent: root_group)
      stub_const("#{described_class}::STATE_PROPAGATION_ITERATOR_BATCH_SIZE", 1)

      allow(Namespace).to receive(:overwrite_state_in_batch).and_wrap_original do |method, *args, **kwargs|
        method.call(*args, **kwargs).tap do
          subgroup.update_column(:state, Namespace.states[:deletion_scheduled])
        end
      end

      expect(Gitlab::NamespaceStatePropagation::Metrics).to receive(:increment_boundary_rewinds).once

      service.execute
    end

    it 'increments the batches counter once per batch' do
      stub_const("#{described_class}::STATE_PROPAGATION_ITERATOR_BATCH_SIZE", 1)
      allow(Namespace).to receive(:overwrite_state_in_batch).and_call_original
      allow(Gitlab::NamespaceStatePropagation::Metrics).to receive(:increment_batches)

      service.execute

      expect(Namespace).to have_received(:overwrite_state_in_batch).twice
      expect(Gitlab::NamespaceStatePropagation::Metrics).to have_received(:increment_batches).with('archived').twice
    end

    describe 'logging' do
      before do
        allow(Gitlab::AppLogger).to receive(:info).and_call_original
      end

      it 'logs the propagation start' do
        expect(Gitlab::AppLogger).to receive(:info).with(hash_including(
          Labkit::Fields::CLASS_NAME => 'Namespaces::StatePropagationService',
          Labkit::Fields::LOG_MESSAGE => 'Namespace state propagation started',
          Labkit::Fields::GL_NAMESPACE_ID => root_group.id,
          'source_state' => 'ancestor_inherited',
          'target_state' => 'archived'
        ))

        service.execute
      end

      it 'logs the propagation completion' do
        root_group.update!(state: :archived)
        stub_const("#{described_class}::STATE_PROPAGATION_ITERATOR_BATCH_SIZE", 1)
        allow(Gitlab::Metrics::System).to receive(:monotonic_time).and_return(100.0)
        allow(Namespace).to receive(:overwrite_state_in_batch).and_wrap_original do |method, *args, **kwargs|
          allow(Gitlab::Metrics::System).to receive(:monotonic_time).and_return(101.2345678)
          method.call(*args, **kwargs)
        end

        expect(Gitlab::AppLogger).to receive(:info).with(hash_including(
          Labkit::Fields::CLASS_NAME => 'Namespaces::StatePropagationService',
          Labkit::Fields::LOG_MESSAGE => 'Namespace state propagation completed',
          Labkit::Fields::GL_NAMESPACE_ID => root_group.id,
          'target_state' => 'archived',
          'batch_count' => 2,
          Labkit::Fields::DURATION_S => 1.234568,
          'descendants_updated' => 2
        ))

        service.execute
      end
    end

    it 'does not change the origin namespace, even when it is in an overwritable state' do
      service.execute

      expect(root_group.reload.state).to eq('ancestor_inherited')
    end

    context 'when a descendant is in a non-overwritable state' do
      before do
        leaf_group.update!(state: :deletion_scheduled)
      end

      it 'does not overwrite the higher-precedence descendant', :aggregate_failures do
        service.execute

        expect(subgroup.reload.state).to eq('archived')
        expect(leaf_group.reload.state).to eq('deletion_scheduled')
      end
    end

    context 'when cancelling a deletion' do
      let!(:propagation) do
        create(:namespace_state_propagation, namespace: root_group,
          source_state: :deletion_scheduled, target_state: target_state)
      end

      def preserved_state(namespace)
        namespace.reload.state_metadata.dig('preserved_states', 'schedule_deletion')
      end

      before do
        root_group.update!(state: target_state)
        subgroup.update!(state: :deletion_scheduled)
        subgroup.namespace_details.update!(state_metadata: { preserved_states: { schedule_deletion: 'archived' } })
        leaf_group.update!(state: :deletion_scheduled)
      end

      context 'when the parent restores to ancestor_inherited' do
        let(:target_state) { 'ancestor_inherited' }

        it 'restores each descendant to its preserved state, or ancestor_inherited', :aggregate_failures do
          service.execute

          expect(subgroup.reload.state).to eq('archived')
          expect(leaf_group.reload.state).to eq('ancestor_inherited')
        end

        it 'removes the preserved deletion state' do
          service.execute

          expect(preserved_state(subgroup)).to be_nil
        end

        context 'when a descendant was already restored by an earlier run' do
          before do
            subgroup.update!(state: :archived)
            subgroup.namespace_details.update!(state_metadata: {})
          end

          it 'keeps the restored descendant and restores the rest', :aggregate_failures do
            service.execute

            expect(subgroup.reload.state).to eq('archived')
            expect(leaf_group.reload.state).to eq('ancestor_inherited')
          end
        end
      end

      context 'when the parent restores to archived' do
        let(:target_state) { 'archived' }

        it 'restores every descendant to at least archived', :aggregate_failures do
          service.execute

          expect(subgroup.reload.state).to eq('archived')
          expect(leaf_group.reload.state).to eq('archived')
        end
      end
    end

    context 'when cancelling a deletion and a descendant scheduled its own deletion' do
      let_it_be_with_reload(:own_scheduled_group) { create(:group, parent: root_group) }
      let_it_be_with_reload(:own_scheduled_child) { create(:group, parent: own_scheduled_group) }

      let(:own_scheduled_at) { 1.day.ago.change(usec: 0) }
      let(:own_preserved_states) { { 'schedule_deletion' => 'ancestor_inherited' } }

      let!(:propagation) do
        create(:namespace_state_propagation, namespace: root_group,
          source_state: :deletion_scheduled, target_state: target_state)
      end

      before do
        root_group.update!(state: target_state)
        [subgroup, leaf_group, own_scheduled_child].each { |g| g.update!(state: :deletion_scheduled) }

        own_scheduled_group.update!(state: :deletion_scheduled)
        own_scheduled_group.namespace_details.update!(
          deletion_scheduled_at: own_scheduled_at,
          state_metadata: { 'preserved_states' => own_preserved_states }
        )
      end

      where(target_state: %w[ancestor_inherited archived])

      with_them do
        it 'keeps the own deletion schedule and its subtree, restoring the other descendants', :aggregate_failures do
          service.execute

          expect(subgroup.reload.state).to eq(target_state)
          expect(leaf_group.reload.state).to eq(target_state)

          own_scheduled_group.reload
          expect(own_scheduled_group.state).to eq('deletion_scheduled')
          expect(own_scheduled_group.deletion_scheduled_at).to eq(own_scheduled_at)
          expect(own_scheduled_group.namespace_details.state_metadata['preserved_states']).to eq(own_preserved_states)
          expect(own_scheduled_child.reload.state).to eq('deletion_scheduled')
        end
      end
    end

    context 'when there are no overwritable states' do
      let!(:propagation) do
        create(:namespace_state_propagation, namespace: root_group,
          source_state: :ancestor_inherited, target_state: :ancestor_inherited)
      end

      it 'does not change any descendant state', :aggregate_failures do
        service.execute

        expect(subgroup.reload.state).to eq('ancestor_inherited')
        expect(leaf_group.reload.state).to eq('ancestor_inherited')
      end

      it 'deletes the outbox record' do
        service.execute

        expect(Namespaces::StatePropagation.exists?(propagation.id)).to be(false)
      end

      it 'does not emit propagation metrics', :aggregate_failures do
        expect(Gitlab::NamespaceStatePropagation::Metrics).not_to receive(:observe_duration)
        expect(Gitlab::NamespaceStatePropagation::Metrics).not_to receive(:increment_batches)

        service.execute
      end

      it_behaves_like 'does not log propagation start or completion'
    end

    context 'when the outbox record does not exist' do
      subject(:service) { described_class.new(non_existing_record_id) }

      it 'does not change any descendant state and does not raise', :aggregate_failures do
        expect { service.execute }.not_to raise_error

        expect(subgroup.reload.state).to eq('ancestor_inherited')
      end

      it 'does not emit propagation metrics', :aggregate_failures do
        expect(Gitlab::NamespaceStatePropagation::Metrics).not_to receive(:observe_duration)
        expect(Gitlab::NamespaceStatePropagation::Metrics).not_to receive(:increment_batches)

        service.execute
      end

      it_behaves_like 'does not log propagation start or completion'
    end

    context 'when the outbox record is already processing' do
      let!(:propagation) do
        create(:namespace_state_propagation, :processing, :ancestor_inherited_to_archived,
          namespace: root_group)
      end

      it 'leaves descendants and the record untouched', :aggregate_failures do
        service.execute

        expect(subgroup.reload.state).to eq('ancestor_inherited')
        expect(propagation.reload).to be_status_processing
      end
    end

    context 'when another job claims the record first' do
      before do
        stale_propagation = Namespaces::StatePropagation.find(propagation.id)
        propagation.claim

        allow(Namespaces::StatePropagation).to receive(:next_for).and_return(stale_propagation)
      end

      it 'leaves descendants untouched' do
        service.execute

        expect(subgroup.reload.state).to eq('ancestor_inherited')
      end

      it 'does not emit propagation metrics', :aggregate_failures do
        expect(Gitlab::NamespaceStatePropagation::Metrics).not_to receive(:observe_duration)
        expect(Gitlab::NamespaceStatePropagation::Metrics).not_to receive(:increment_batches)

        service.execute
      end

      it_behaves_like 'does not log propagation start or completion'
    end

    context 'when propagation fails partway through' do
      before do
        stub_const("#{described_class}::STATE_PROPAGATION_ITERATOR_BATCH_SIZE", 1)
        calls = 0

        allow(Namespace).to receive(:overwrite_state_in_batch).and_wrap_original do |method, *args, **kwargs|
          calls += 1
          raise ActiveRecord::StatementInvalid, 'statement failed' if calls > 1

          method.call(*args, **kwargs)
        end
      end

      it 'returns the outbox record to pending so the Sidekiq retry applies it', :aggregate_failures do
        expect { service.execute }.to raise_error(ActiveRecord::StatementInvalid)

        expect(propagation.reload).to be_status_pending

        allow(Namespace).to receive(:overwrite_state_in_batch).and_call_original
        service.execute

        expect(Namespaces::StatePropagation.exists?(propagation.id)).to be(false)
        expect([subgroup.reload.state, leaf_group.reload.state]).to all(eq('archived'))
      end

      it 'does not observe the propagation duration' do
        expect(Gitlab::NamespaceStatePropagation::Metrics).not_to receive(:observe_duration)

        expect { service.execute }.to raise_error(ActiveRecord::StatementInvalid)
      end

      it 'counts the failure once for the target state' do
        expect(Gitlab::NamespaceStatePropagation::Metrics).to receive(:increment_failures).with('archived').once

        expect { service.execute }.to raise_error(ActiveRecord::StatementInvalid)
      end

      it 'logs the failure and re-raises without logging completion', :aggregate_failures do
        allow(Gitlab::AppLogger).to receive(:info).and_call_original
        expect(Gitlab::AppLogger).to receive(:error).with(hash_including(
          Labkit::Fields::CLASS_NAME => 'Namespaces::StatePropagationService',
          Labkit::Fields::LOG_MESSAGE => 'Namespace state propagation failed',
          Labkit::Fields::GL_NAMESPACE_ID => root_group.id,
          'target_state' => 'archived',
          Labkit::Fields::ERROR_TYPE => 'ActiveRecord::StatementInvalid',
          Labkit::Fields::ERROR_MESSAGE => 'statement failed'
        ))
        expect(Gitlab::AppLogger).not_to receive(:info)
          .with(hash_including(Labkit::Fields::LOG_MESSAGE => 'Namespace state propagation completed'))

        expect { service.execute }.to raise_error(ActiveRecord::StatementInvalid)
      end
    end

    context 'when deleting a completed outbox record fails' do
      before do
        allow_next_found_instance_of(Namespaces::StatePropagation) do |record|
          allow(record).to receive(:destroy!).and_raise(ActiveRecord::StatementInvalid)
        end
      end

      it 'counts the failure once for the target state' do
        expect(Gitlab::NamespaceStatePropagation::Metrics).to receive(:increment_failures).with('archived').once

        expect { service.execute }.to raise_error(ActiveRecord::StatementInvalid)
      end
    end

    context 'when looking up the next outbox record fails' do
      before do
        allow(Namespaces::StatePropagation).to receive(:next_for).and_raise(ActiveRecord::StatementInvalid)
      end

      it 'counts the failure as unknown' do
        expect(Gitlab::NamespaceStatePropagation::Metrics).to receive(:increment_failures).with('unknown').once

        expect { service.execute }.to raise_error(ActiveRecord::StatementInvalid)
      end
    end

    context 'when the namespace has several outbox records' do
      let!(:newer_propagation) do
        create(:namespace_state_propagation, :archived_to_ancestor_inherited, namespace: root_group)
      end

      it 'applies them oldest first and deletes each one', :aggregate_failures do
        applied = []

        allow(Namespace).to receive(:overwrite_state_in_batch).and_wrap_original do |method, *args, **kwargs|
          applied << kwargs[:to]
          method.call(*args, **kwargs)
        end

        service.execute

        expect(applied.uniq).to eq(%w[archived ancestor_inherited])
        expect(subgroup.reload.state).to eq('ancestor_inherited')
        expect(Namespaces::StatePropagation.where(namespace_id: root_group.id)).to be_empty
      end

      it 'does not re-enqueue the namespace when every record is applied within the runtime limit' do
        expect(Namespaces::StatePropagationWorker).not_to receive(:perform_async)

        service.execute
      end

      context 'when the runtime limit is exceeded after a record finishes' do
        before do
          stub_const("#{described_class}::MAX_RUNTIME", 0)
        end

        it 'applies only the oldest record and re-enqueues the namespace for the rest', :aggregate_failures do
          expect(Namespaces::StatePropagationWorker).to receive(:perform_async).with(root_group.id)

          service.execute

          expect(subgroup.reload.state).to eq('archived')
          expect(Namespaces::StatePropagation.exists?(propagation.id)).to be(false)
          expect(newer_propagation.reload).to be_status_pending
        end
      end

      context 'when the oldest record is processing' do
        before do
          propagation.claim
        end

        it 'does not apply the newer record', :aggregate_failures do
          service.execute

          expect(subgroup.reload.state).to eq('ancestor_inherited')
          expect(newer_propagation.reload).to be_status_pending
        end

        context 'when it has no overwritable states' do
          let!(:propagation) do
            create(:namespace_state_propagation, namespace: root_group,
              source_state: :ancestor_inherited, target_state: :ancestor_inherited)
          end

          it 'keeps the processing record' do
            service.execute

            expect(propagation.reload).to be_status_processing
          end
        end
      end
    end
  end

  describe 'propagating several transitions of the same namespace' do
    let_it_be(:user) { create(:user) }

    let(:outbox_rows) { Namespaces::StatePropagation.where(namespace_id: root_group.id) }

    def fail_propagation_after(successful_batches, error: ActiveRecord::StatementInvalid)
      calls = 0

      allow(Namespace).to receive(:overwrite_state_in_batch).and_wrap_original do |method, *args, **kwargs|
        calls += 1
        raise error if calls > successful_batches

        method.call(*args, **kwargs)
      end

      expect { service.execute }.to raise_error(error)

      allow(Namespace).to receive(:overwrite_state_in_batch).and_call_original
    end

    def recover_stuck_propagations
      travel_to((Namespaces::StatePropagationCronWorker::STUCK_THRESHOLD + 1.minute).from_now) do
        Namespaces::StatePropagationCronWorker.new.perform
      end
    end

    before do
      stub_const("#{described_class}::STATE_PROPAGATION_ITERATOR_BATCH_SIZE", 1)
    end

    context 'when a namespace is archived, unarchived, and archived again' do
      before do
        root_group.archive(transition_user: user)
        root_group.unarchive(transition_user: user)
        root_group.archive(transition_user: user)
      end

      it 'queues every transition' do
        expect(outbox_rows.order(:id).pluck(:target_state)).to eq(%w[archived ancestor_inherited archived])
      end

      it 'leaves descendants in the last propagated state', :aggregate_failures do
        service.execute

        expect([subgroup, leaf_group].map { |group| group.reload.state }).to all(eq('archived'))
        expect(outbox_rows).to be_empty
      end
    end

    context 'when a namespace with an archived descendant is archived and then unarchived' do
      before do
        leaf_group.update!(state: :archived)
        root_group.archive(transition_user: user)
        root_group.unarchive(transition_user: user)
      end

      it 'applies both transitions in order, unarchiving every descendant' do
        service.execute

        expect([subgroup, leaf_group].map { |group| group.reload.state }).to all(eq('ancestor_inherited'))
      end
    end

    context 'when a failed propagation is retried after a later transition' do
      before do
        root_group.archive(transition_user: user)
        fail_propagation_after(1)
        root_group.unarchive(transition_user: user)
      end

      it 'applies the failed propagation before the later one', :aggregate_failures do
        service.execute

        expect([subgroup, leaf_group].map { |group| group.reload.state }).to all(eq('ancestor_inherited'))
        expect(outbox_rows).to be_empty
      end
    end

    context 'when an interrupted propagation is recovered after a later transition' do
      before do
        root_group.archive(transition_user: user)
        fail_propagation_after(1, error: Sidekiq::Shutdown)
        root_group.unarchive(transition_user: user)
      end

      it 'does not apply the later transition while the failed one is stuck' do
        service.execute

        expect(outbox_rows.order(:id).pluck(:target_state)).to eq(%w[archived ancestor_inherited])
      end

      it 'applies the recovered propagation before the later one', :aggregate_failures do
        recover_stuck_propagations
        service.execute

        expect([subgroup, leaf_group].map { |group| group.reload.state }).to all(eq('ancestor_inherited'))
        expect(outbox_rows).to be_empty
      end
    end

    context 'when a deletion is scheduled and cancelled while an archive is half applied' do
      def preserved_state(namespace)
        namespace.reload.state_metadata.dig('preserved_states', 'schedule_deletion')
      end

      before do
        root_group.archive(transition_user: user)
        fail_propagation_after(1, error: Sidekiq::Shutdown)
        root_group.schedule_deletion(transition_user: user)
        recover_stuck_propagations
      end

      it 'preserves the archived state for every descendant', :aggregate_failures do
        service.execute

        expect([subgroup, leaf_group].map { |group| group.reload.state }).to all(eq('deletion_scheduled'))
        expect([subgroup, leaf_group].map { |group| preserved_state(group) }).to all(eq('archived'))
      end

      it 'restores every descendant to archived when the deletion is cancelled' do
        service.execute
        root_group.cancel_deletion(transition_user: user)
        service.execute

        expect([subgroup, leaf_group].map { |group| group.reload.state }).to all(eq('archived'))
      end
    end
  end
end
