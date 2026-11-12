# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Authz::ProjectAuthorizations::Reach, feature_category: :permissions do
  let_it_be(:group) { create(:group) }
  let_it_be(:subgroup) { create(:group, parent: group) }
  let_it_be(:shared_group) { create(:group) }
  let_it_be(:unrelated_group) { create(:group) }
  let_it_be(:project) { create(:project, group: group) }
  let_it_be(:sub_project) { create(:project, group: subgroup) }
  let_it_be(:shared_group_project) { create(:project, group: shared_group) }
  let_it_be(:project_shared_with_subgroup) { create(:project, group: unrelated_group) }
  let_it_be(:unrelated_project) { create(:project, group: unrelated_group) }

  before_all do
    create(:group_group_link, shared_group: shared_group, shared_with_group: group)
    create(:project_group_link, project: project_shared_with_subgroup, group: subgroup)
  end

  describe '#project_ids' do
    it "returns the subtree's projects, projects shared with the subtree, and the reach of groups it's invited into" do
      expect(described_class.new([group.id]).project_ids).to contain_exactly(project.id, sub_project.id,
        shared_group_project.id, project_shared_with_subgroup.id)
    end

    it 'reads a subtree once when groups in it are given too' do
      reach = described_class.new([subgroup.id, group.id])

      expect(reach).to receive(:subtree_group_ids).with(contain_exactly(group.id, shared_group.id)).and_call_original
      expect(reach.project_ids).to contain_exactly(project.id, sub_project.id, shared_group_project.id,
        project_shared_with_subgroup.id)
    end

    it 'returns nothing without groups' do
      expect(described_class.new([]).project_ids).to eq([])
    end

    it "doesn't include groups the subgroup's ancestors are invited into" do
      expect(described_class.new([subgroup.id]).project_ids).to contain_exactly(sub_project.id,
        project_shared_with_subgroup.id)
    end
  end

  describe '.for_user' do
    let_it_be(:user) { create(:user, :with_namespace) }
    let_it_be(:personal_project) { create(:project, namespace: user.namespace) }
    let_it_be(:member_project) { create(:project) }
    let_it_be(:stale_project) { create(:project) }

    before_all do
      subgroup.add_developer(user)
      member_project.add_reporter(user)
      create(:group_member, :access_request, group: unrelated_group, user: user)
      ProjectAuthorization.insert_all([{ user_id: user.id, project_id: stale_project.id, access_level: 30,
                                         is_unique: true }])
    end

    it 'returns every project the user can have access to, and the projects of their current rows' do
      expect(described_class.for_user(user.id)).to contain_exactly(sub_project.id, project_shared_with_subgroup.id,
        personal_project.id, member_project.id, stale_project.id)
    end
  end
end
