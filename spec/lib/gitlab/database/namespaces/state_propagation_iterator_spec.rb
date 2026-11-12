# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Gitlab::Database::Namespaces::StatePropagationIterator, feature_category: :groups_and_projects do
  let_it_be_with_reload(:group) { create(:group) }
  let_it_be_with_reload(:subgroup1) { create(:group, parent: group) }
  let_it_be_with_reload(:subgroup2) { create(:group, parent: group) }
  let_it_be_with_reload(:subsubgroup1) { create(:group, parent: subgroup1) }
  let_it_be_with_reload(:subsubgroup2) { create(:group, parent: subgroup1) }
  let_it_be(:project1) { create(:project, namespace: subsubgroup1) }
  let_it_be(:project2) { create(:project, namespace: subgroup2) }
  let_it_be(:project3) { create(:project, namespace: subsubgroup2) }

  let(:namespace_id) { group.id }
  let(:state_filter) { [:ancestor_inherited] }
  let(:options) { {} }
  let(:cursor) { { current_id: namespace_id, depth: [namespace_id] } }

  def collected_ids
    [].tap do |ids|
      described_class.new(
        cursor: cursor,
        state_filter: state_filter,
        options: options
      ).each_batch(of: 3) do |batch_ids|
        ids.concat(batch_ids)
      end
    end
  end

  describe '#each_batch' do
    context 'when a subgroup is in a non-overwritable state' do
      before do
        subgroup2.update!(state: :archived)
      end

      it 'prunes the subgroup and all of its descendants from the traversal' do
        expect(collected_ids).to eq([
          group.id,
          subgroup1.id,
          subsubgroup1.id,
          project1.project_namespace_id,
          subsubgroup2.id,
          project3.project_namespace_id
        ])
      end
    end

    context 'when the first child by id is in a non-overwritable state' do
      before do
        subgroup1.update!(state: :archived)
      end

      it 'prunes the first child and its descendants while still visiting later siblings' do
        expect(collected_ids).to eq([
          group.id,
          subgroup2.id,
          project2.project_namespace_id
        ])
      end
    end

    context 'when the root namespace is not in the state_filter' do
      before do
        group.update!(state: :archived)
      end

      it 'still walks the overwritable descendants' do
        expect(collected_ids).to eq([
          group.id,
          subgroup1.id,
          subsubgroup1.id,
          project1.project_namespace_id,
          subsubgroup2.id,
          project3.project_namespace_id,
          subgroup2.id,
          project2.project_namespace_id
        ])
      end
    end

    context 'when the filter accepts multiple states' do
      let(:state_filter) { [:ancestor_inherited, :archived] }

      before do
        subgroup2.update!(state: :archived)
      end

      it 'includes namespaces whose state matches any value in the filter' do
        expect(collected_ids).to eq([
          group.id,
          subgroup1.id,
          subsubgroup1.id,
          project1.project_namespace_id,
          subsubgroup2.id,
          project3.project_namespace_id,
          subgroup2.id,
          project2.project_namespace_id
        ])
      end
    end
  end

  describe '#each_batch with preserve_descendants_deletion' do
    def schedule_own_deletion(namespace)
      namespace.namespace_details.update!(deletion_scheduled_at: Time.current)
    end

    context 'when the option is enabled' do
      let(:options) { { preserve_descendants_deletion: true } }

      context 'when a subgroup scheduled its own deletion' do
        before do
          schedule_own_deletion(subgroup1)
        end

        it 'prunes the subgroup and its subtree while still visiting later siblings' do
          expect(collected_ids).to eq([
            group.id,
            subgroup2.id,
            project2.project_namespace_id
          ])
        end
      end

      context 'when a later sibling scheduled its own deletion' do
        before do
          schedule_own_deletion(subsubgroup2)
        end

        it 'prunes only that sibling and its subtree' do
          expect(collected_ids).to eq([
            group.id,
            subgroup1.id,
            subsubgroup1.id,
            project1.project_namespace_id,
            subgroup2.id,
            project2.project_namespace_id
          ])
        end
      end

      context 'when the root has deletion_scheduled_at set' do
        before do
          schedule_own_deletion(group)
        end

        it 'does not treat the root as a boundary' do
          expect(collected_ids).to eq([
            group.id,
            subgroup1.id,
            subsubgroup1.id,
            project1.project_namespace_id,
            subsubgroup2.id,
            project3.project_namespace_id,
            subgroup2.id,
            project2.project_namespace_id
          ])
        end
      end

      context 'when an ancestor on the cursor path schedules its own deletion mid-iteration' do
        it 'rewinds past its subtree', :aggregate_failures do
          batches = []
          described_class.new(
            cursor: cursor,
            state_filter: state_filter,
            options: options
          ).each_batch(of: 3) do |ids|
            batches << ids.dup
            schedule_own_deletion(subgroup1) if batches.size == 1
          end

          all_ids = batches.flatten

          expect(all_ids.first(4)).to eq([group.id, subgroup1.id, subsubgroup1.id, project1.project_namespace_id])
          expect(all_ids).not_to include(subsubgroup2.id, project3.project_namespace_id)
          expect(all_ids).to include(subgroup2.id, project2.project_namespace_id)
        end

        context 'when the next sibling also scheduled its own deletion' do
          before do
            schedule_own_deletion(subgroup2)
          end

          it 'does not resume from that sibling' do
            all_ids = []
            described_class.new(
              cursor: cursor,
              state_filter: state_filter,
              options: options
            ).each_batch(of: 3) do |ids|
              all_ids.concat(ids)
              schedule_own_deletion(subgroup1) if all_ids.size == ids.size
            end

            expect(all_ids).not_to include(subgroup2.id, project2.project_namespace_id)
          end
        end
      end
    end

    context 'when the option is disabled' do
      before do
        schedule_own_deletion(subgroup1)
      end

      it 'still visits namespaces that have deletion_scheduled_at set' do
        expect(collected_ids).to eq([
          group.id,
          subgroup1.id,
          subsubgroup1.id,
          project1.project_namespace_id,
          subsubgroup2.id,
          project3.project_namespace_id,
          subgroup2.id,
          project2.project_namespace_id
        ])
      end
    end
  end

  describe '#each_batch with cursor rewind' do
    let(:on_rewind) { instance_double(Proc, call: nil) }

    let(:iterator) do
      described_class.new(
        cursor: cursor,
        state_filter: state_filter,
        on_rewind: on_rewind,
        options: options
      )
    end

    def run_with_mutation
      batches = []
      iterator.each_batch(of: 3) do |ids, batch_cursor|
        batches << { ids: ids.dup, cursor: batch_cursor.dup }
        yield batches if block_given?
      end
      batches
    end

    context 'when an ancestor on the cursor path transitions to a non-overwritable state mid-iteration' do
      it 'skips the batch after the boundary appears and resumes from the next sibling', :aggregate_failures do
        batches = run_with_mutation do |seen|
          subgroup1.update!(state: :archived) if seen.size == 1
        end

        all_ids = batches.flat_map { |b| b[:ids] }

        # Since `subgroup1` has changed to a non-overwritable state. It's descendants should be skipped.
        expect(all_ids).not_to include(subsubgroup2.id)
        expect(all_ids).not_to include(project3.project_namespace_id)

        # The iterator should still yield all of the nodes under the sibling subgroup of `subgroup1`.
        expect(all_ids).to include(subgroup2.id, project2.project_namespace_id)

        # Includes namespaces before the concurrent update on `subgroup1` was made.
        expect(all_ids.first(4)).to eq([
          group.id,
          subgroup1.id,
          subsubgroup1.id,
          project1.project_namespace_id
        ])
      end

      it 'calls on_rewind once' do
        run_with_mutation do |seen|
          subgroup1.update!(state: :archived) if seen.size == 1
        end

        expect(on_rewind).to have_received(:call).once
      end

      context 'without an on_rewind callback' do
        let(:on_rewind) { nil }

        it 'still rewinds past the boundary' do
          batches = run_with_mutation do |seen|
            subgroup1.update!(state: :archived) if seen.size == 1
          end

          expect(batches.flat_map { |b| b[:ids] }).to include(subgroup2.id)
        end
      end
    end

    context 'when the cursor is rewound past a boundary' do
      it 'logs the rewind' do
        allow(Gitlab::AppLogger).to receive(:info).and_call_original
        # The second batch ends at project3 ([group, subgroup1, subsubgroup2, project3]) and
        # rewinds to subgroup1's next sibling ([group, subgroup2]).
        expect(Gitlab::AppLogger).to receive(:info).with(hash_including(
          Labkit::Fields::CLASS_NAME => 'Gitlab::Database::Namespaces::StatePropagationIterator',
          Labkit::Fields::LOG_MESSAGE => 'Namespace state propagation cursor rewound',
          Labkit::Fields::GL_NAMESPACE_ID => group.id,
          'boundary_id' => subgroup1.id,
          'boundary_state' => 'archived',
          'depth_before' => 4,
          'depth_after' => 2
        )).once

        run_with_mutation do |seen|
          subgroup1.update!(state: :archived) if seen.size == 1
        end
      end
    end

    context 'when multiple ancestors on the cursor path become boundaries' do
      it 'rewinds to the shallowest boundary and skips its entire subtree', :aggregate_failures do
        batches = run_with_mutation do |seen|
          if seen.size == 1
            subgroup1.update!(state: :archived)
            subsubgroup1.update!(state: :archived)
          end
        end

        all_ids = batches.flat_map { |b| b[:ids] }

        # The shallowest boundary (`subgroup1`) wins, so its entire subtree
        # is skipped, including descendants under the deeper boundary.
        expect(all_ids).not_to include(subsubgroup2.id)
        expect(all_ids).not_to include(project3.project_namespace_id)

        # Iteration still resumes from `subgroup1`'s next sibling subtree.
        expect(all_ids).to include(subgroup2.id, project2.project_namespace_id)
      end
    end

    context 'when no concurrent state change occurs' do
      it 'yields the same ids as a plain (non-rewinding) traversal' do
        batches = run_with_mutation
        all_ids = batches.flat_map { |b| b[:ids] }

        expect(all_ids).to eq([
          group.id,
          subgroup1.id,
          subsubgroup1.id,
          project1.project_namespace_id,
          subsubgroup2.id,
          project3.project_namespace_id,
          subgroup2.id,
          project2.project_namespace_id
        ])
      end

      it 'does not call on_rewind' do
        run_with_mutation

        expect(on_rewind).not_to have_received(:call)
      end
    end

    context 'when the leaf of the cursor depth transitions to a non-overwritable state' do
      it 'rewinds past the leaf without descending into its children', :aggregate_failures do
        # of: 2 makes the first batch end with subsubgroup1 (a group with a
        # child) as the cursor's leaf, so we can verify the rewind doesn't
        # step into project1.
        local_iterator = described_class.new(
          cursor: cursor,
          state_filter: state_filter
        )

        batches = []
        local_iterator.each_batch(of: 2) do |ids, batch_cursor|
          batches << { ids: ids.dup, cursor: batch_cursor.dup }
          subsubgroup1.update!(state: :archived) if batches.size == 1
        end

        all_ids = batches.flat_map { |b| b[:ids] }

        # `project1` lives directly under the now-archived `subsubgroup1`,
        # so the rewind must skip it instead of descending one more level.
        expect(all_ids).not_to include(project1.project_namespace_id)

        # The next sibling of `subsubgroup1` and everything past it should
        # still be visited.
        expect(all_ids).to include(
          subsubgroup2.id,
          project3.project_namespace_id,
          subgroup2.id,
          project2.project_namespace_id
        )
      end
    end

    context 'when no next sibling exists at any ancestor level past the boundary' do
      it 'terminates iteration cleanly', :aggregate_failures do
        batches = run_with_mutation do |seen|
          if seen.size == 1
            subgroup1.update!(state: :archived)
            subgroup2.update!(state: :archived)
          end
        end

        all_ids = batches.flat_map { |b| b[:ids] }

        # With every sibling of `subgroup1` also archived, the rewind walks
        # up to the root with no eligible sibling to resume from, so only
        # the pre-mutation batch is yielded.
        expect(batches.size).to eq(1)
        expect(all_ids).not_to include(subgroup2.id, project2.project_namespace_id)
      end

      it 'does not call on_rewind' do
        run_with_mutation do |seen|
          if seen.size == 1
            subgroup1.update!(state: :archived)
            subgroup2.update!(state: :archived)
          end
        end

        expect(on_rewind).not_to have_received(:call)
      end
    end

    context 'when a rewind has occurred and a later batch is yielded' do
      it 'yields a cursor consistent with the post-rewind position', :aggregate_failures do
        batches = run_with_mutation do |seen|
          subgroup1.update!(state: :archived) if seen.size == 1
        end

        post_rewind_batches = batches.drop(1)

        expect(post_rewind_batches).not_to be_empty

        # After the rewind, the yielded cursor's depth must reflect the new
        # position and not leak any ancestor from the abandoned subtree,
        # otherwise resuming from a persisted cursor would re-enter it.
        post_rewind_batches.each do |batch|
          expect(batch[:cursor][:depth]).not_to include(subgroup1.id)
          expect(batch[:cursor][:depth]).not_to include(subsubgroup1.id)
          expect(batch[:cursor][:depth]).not_to include(project1.project_namespace_id)
        end
      end
    end
  end
end
