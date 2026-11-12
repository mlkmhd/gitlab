# frozen_string_literal: true

require 'spec_helper'

RSpec.describe ::WorkItems::RelatedWorkItemLink, feature_category: :portfolio_management do
  it_behaves_like 'includes LinkableItem concern (EE)' do
    let_it_be(:item_factory) { :work_item }
    let_it_be(:link_factory) { :work_item_link }
    let_it_be(:link_class) { described_class }
  end

  describe 'associations' do
    it 'has one related_epic_link association' do
      is_expected.to have_one(:related_epic_link).class_name('::Epic::RelatedEpicLink')
        .with_foreign_key('issue_link_id').inverse_of(:related_work_item_link)
    end
  end

  describe 'scopes' do
    let(:epic_type) { build(:work_item_system_defined_type, :epic) }

    let_it_be(:epic_issue_link) do
      create(:work_item_link, source: create(:work_item, :epic), target: create(:work_item, :issue))
    end

    let_it_be(:epic_epic_link) do
      create(:work_item_link, source: create(:work_item, :epic), target: create(:work_item, :epic))
    end

    let_it_be(:issue_epic_link) do
      create(:work_item_link, source: create(:work_item, :issue), target: create(:work_item, :epic))
    end

    context 'when filtered by source type' do
      it 'returns only links with the given type on the source' do
        expect(described_class.for_source_type(epic_type)).to contain_exactly(epic_issue_link, epic_epic_link)
      end
    end

    context 'when filtered by target type' do
      it 'returns only links with the given type on the target' do
        expect(described_class.for_target_type(epic_type)).to contain_exactly(issue_epic_link, epic_epic_link)
      end
    end

    context 'when combining for_target_type and for_source_type' do
      it 'returns only links with the given type on the source and target' do
        expect(described_class.for_source_type(epic_type).for_target_type(epic_type)).to contain_exactly(epic_epic_link)
      end
    end

    describe '.for_work_item_type_in_namespaces' do
      let_it_be(:group) { create(:group) }
      let_it_be(:other_group) { create(:group) }
      let_it_be(:epic_in_group) { create(:work_item, :epic, namespace: group) }
      let_it_be(:epic_in_other_group) { create(:work_item, :epic, namespace: other_group) }
      let_it_be(:issue_in_group) { create(:work_item, :issue, namespace: group) }

      let_it_be(:epic_link_in_group) do
        create(:work_item_link, source: epic_in_group, target: create(:work_item, :epic, namespace: group))
      end

      let_it_be(:epic_link_outside_group) do
        create(:work_item_link, source: epic_in_other_group, target: create(:work_item, :epic, namespace: other_group))
      end

      let_it_be(:non_epic_link_in_group) do
        create(:work_item_link, source: issue_in_group, target: create(:work_item, :issue, namespace: group))
      end

      let(:namespace_ids) { group.self_and_descendants.select(:id) }
      let(:cte) { ::Gitlab::SQL::CTE.new(:namespace_ids, namespace_ids) }
      let(:epic_type_id) { epic_in_group.work_item_type_id }

      subject(:result) { described_class.for_work_item_type_in_namespaces(cte, epic_type_id) }

      it 'returns only epic links within the namespaces' do
        aggregate_failures do
          expect(result).to include(epic_link_in_group).once
          expect(result).not_to include(epic_link_outside_group)
          expect(result).not_to include(non_epic_link_in_group)
        end
      end

      context 'when the source is outside the namespace but the target is inside' do
        let_it_be(:cross_group_link) do
          create(:work_item_link, source: epic_in_other_group, target: epic_in_group)
        end

        it 'includes the cross-group link' do
          expect(result).to include(cross_group_link)
        end
      end
    end
  end

  describe '.blocking_ids_outside_namespace' do
    let_it_be(:group) { create(:group) }
    let_it_be(:project) { create(:project) }
    let_it_be(:blocked_work_item) { create(:work_item, :group_level, namespace: group) }
    let_it_be(:other_blocked_work_item) { create(:work_item, :group_level, namespace: group) }
    let_it_be(:closed_work_item) { create(:work_item, :group_level, :closed, namespace: group) }
    let_it_be(:blocker_in_group) { create(:work_item, :group_level, namespace: group) }
    let_it_be(:blocker) { create(:work_item, project: project) }
    let_it_be(:blocker_in_other_group) { create(:work_item, :group_level) }
    let_it_be(:blocker_of_closed_work_item) { create(:work_item, project: project) }
    let_it_be(:related_work_item) { create(:work_item, project: project) }
    let_it_be(:work_item_blocked_from_group) { create(:work_item, project: project) }

    before_all do
      [
        [blocker, blocked_work_item],
        [blocker, other_blocked_work_item],
        [blocker_in_other_group, other_blocked_work_item],
        [blocker_in_group, blocked_work_item],
        [blocker_of_closed_work_item, closed_work_item],
        [blocked_work_item, work_item_blocked_from_group]
      ].each do |source, target|
        create(:work_item_link, source: source, target: target, link_type: described_class::TYPE_BLOCKS)
      end

      create(:work_item_link, source: related_work_item, target: blocked_work_item)
    end

    it 'returns the work items outside the namespace that block its open work items, read in batches' do
      stub_const('EE::WorkItems::RelatedWorkItemLink::BLOCKED_WORK_ITEM_BATCH_SIZE', 1)

      expect(described_class.blocking_ids_outside_namespace(group))
        .to contain_exactly(blocker.id, blocker_in_other_group.id)
    end
  end

  describe '#synced_related_epic_link' do
    let_it_be(:group) { create(:group) }
    let_it_be(:epic_a) { create(:epic, :with_synced_work_item, group: group) }
    let_it_be(:epic_b) { create(:epic, :with_synced_work_item, group: group) }
    let_it_be(:work_item_a) { epic_a.work_item }
    let_it_be(:work_item_b) { epic_b.work_item }
    let_it_be_with_refind(:link) { create(:work_item_link, source: work_item_a, target: work_item_b) }

    subject(:related_epic_link) { link.synced_related_epic_link }

    it { is_expected.to be_nil }

    context 'when there is a synced related epic record' do
      let_it_be(:related_epic_link) do
        create(:related_epic_link, source: epic_a, target: epic_b, related_work_item_link: link)
      end

      it { is_expected.to eq(related_epic_link) }
    end
  end
end
