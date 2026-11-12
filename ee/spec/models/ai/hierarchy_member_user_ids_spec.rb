# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Ai::HierarchyMemberUserIds, feature_category: :ai_abstraction_layer do
  let_it_be(:group) { create(:group) }
  let_it_be(:sub_group) { create(:group, parent: group) }
  let_it_be(:project) { create(:project, group: group) }
  let_it_be(:sub_group_project) { create(:project, group: sub_group) }

  let_it_be(:group_member) { create(:group_member, group: group) }
  let_it_be(:sub_group_member) { create(:group_member, group: sub_group) }
  let_it_be(:project_member) { create(:project_member, project: project) }
  let_it_be(:sub_group_project_member) { create(:project_member, project: sub_group_project) }
  let_it_be(:blocked_member) { create(:group_member, :blocked, group: sub_group) }

  let_it_be(:duplicate_member) { create(:project_member, :owner, project: sub_group_project, user: group_member.user) }
  let_it_be(:invited_member) { create(:group_member, :invited, group: group) }
  let_it_be(:access_request) { create(:group_member, :access_request, group: sub_group) }
  let_it_be(:outside_member) { create(:group_member, group: create(:group)) }

  let(:hierarchy_user_ids) do
    [group_member, sub_group_member, project_member, sub_group_project_member, blocked_member].map(&:user_id)
  end

  subject(:batches) do
    batches = []
    described_class.new(group).each_user_ids_batch { |user_ids| batches << user_ids }
    batches
  end

  it 'yields every member of the group, its subgroups and their projects' do
    expect(batches.flatten.uniq).to match_array(hierarchy_user_ids)
  end

  it 'yields each user once per batch' do
    expect(batches).to all(satisfy('have no duplicates') { |user_ids| user_ids == user_ids.uniq })
    expect(batches.flatten.count(group_member.user_id)).to eq(1)
  end

  context 'when a namespace batch has more members than the batch size' do
    before do
      stub_const("#{described_class}::MEMBER_BATCH_SIZE", 2)
    end

    it 'reads each group and project in batches no larger than the batch size' do
      expect(batches.size).to be > 1
      expect(batches).to all(satisfy('have at most 2 user IDs') { |user_ids| user_ids.size <= 2 })
      expect(batches.flatten.uniq).to match_array(hierarchy_user_ids)
    end
  end

  context 'when a group or project has exactly the batch size of members' do
    before do
      stub_const("#{described_class}::MEMBER_BATCH_SIZE", 2)
    end

    it 'reads it with one query and no id batching' do
      recorder = ActiveRecord::QueryRecorder.new { batches }

      expect(recorder.log.grep(/ORDER BY "members"."id"/)).to be_empty
      expect(batches.flatten.uniq).to match_array(hierarchy_user_ids)
    end
  end

  context 'when a namespace batch is over the batch size but each group and project is within it' do
    before do
      stub_const("#{described_class}::MEMBER_BATCH_SIZE", 4)
    end

    it 'reads each group and project with one query and no id batching' do
      recorder = ActiveRecord::QueryRecorder.new { batches }

      expect(recorder.log.grep(/ORDER BY "members"."id"/)).to be_empty
      expect(batches.size).to eq(4)
      expect(batches.flatten.uniq).to match_array(hierarchy_user_ids)
    end
  end

  context 'when the namespace batch size is smaller than the hierarchy' do
    before do
      stub_const("#{described_class}::NAMESPACE_BATCH_SIZE", 1)
    end

    it 'still yields every member of the hierarchy' do
      expect(batches.flatten.uniq).to match_array(hierarchy_user_ids)
    end
  end

  context 'when several namespace batches each have more members than the batch size' do
    before do
      stub_const("#{described_class}::NAMESPACE_BATCH_SIZE", 2)
      stub_const("#{described_class}::MEMBER_BATCH_SIZE", 1)
    end

    it 'reads every group and project one member at a time' do
      expect(batches).to all(have_attributes(size: 1))
      expect(batches.flatten.uniq).to match_array(hierarchy_user_ids)
    end
  end

  context 'when the first namespace batch holds one more namespace than the batch size' do
    before do
      stub_const("#{described_class}::NAMESPACE_BATCH_SIZE", 1)
      stub_const("#{described_class}::MEMBER_BATCH_SIZE", 1)
    end

    it 'reads the members of every namespace in the batch' do
      expect(batches.flatten.uniq).to match_array(hierarchy_user_ids)
    end
  end

  context 'when the hierarchy has no members' do
    let_it_be(:empty_group) { create(:group) }

    it 'yields nothing' do
      expect { |block| described_class.new(empty_group).each_user_ids_batch(&block) }.not_to yield_control
    end
  end
end
