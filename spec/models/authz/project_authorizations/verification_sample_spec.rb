# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Authz::ProjectAuthorizations::VerificationSample, feature_category: :permissions do
  let_it_be(:group) { create(:group) }
  let_it_be(:group_project) { create(:project, group: group) }
  let_it_be(:member_project) { create(:project) }
  let_it_be(:group_member) { create(:user) }
  let_it_be(:project_member) { create(:user) }

  before_all do
    group.add_developer(group_member)
    member_project.add_developer(project_member)
    create(:group_member, :access_request, group: group)
  end

  subject(:pairs) { described_class.new(10).pairs }

  it 'samples stored rows, including stale grants with no membership' do
    stale_user = create(:user)
    ProjectAuthorization.insert_all([
      { user_id: stale_user.id, project_id: member_project.id, access_level: Gitlab::Access::DEVELOPER }
    ])

    expect(pairs).to include([stale_user.id, member_project.id])
  end

  it 'samples memberships, with a project each membership reaches' do
    ProjectAuthorization.delete_all

    expect(pairs).to include([group_member.id, group_project.id], [project_member.id, member_project.id])
  end

  it "skips access requests" do
    ProjectAuthorization.delete_all
    requester_id = GroupMember.where(source: group).where.not(requested_at: nil).pick(:user_id)

    expect(pairs.map(&:first)).not_to include(requester_id)
  end

  it 'reaches projects of groups the group is invited into when the group has none' do
    empty_group = create(:group)
    invited_into = create(:group)
    shared_project = create(:project, group: invited_into)
    member = create(:user, developer_of: empty_group)
    create(:group_group_link, shared_group: invited_into, shared_with_group: empty_group)
    ProjectAuthorization.delete_all

    expect(pairs).to include([member.id, shared_project.id])
  end

  it 'reaches projects in subgroups and projects shared with the group' do
    parent = create(:group)
    subgroup_project = create(:project, group: create(:group, parent: parent))
    shared_project = create(:project)
    create(:project_group_link, project: shared_project, group: parent)
    member = create(:user, developer_of: parent)
    ProjectAuthorization.delete_all

    reached = Array.new(30) { described_class.new(100).pairs }.flatten(1).select { |user_id, _| user_id == member.id }

    expect(reached.map(&:last).uniq).to contain_exactly(subgroup_project.id, shared_project.id)
  end

  it 'reaches projects shared with a group that also has projects of its own' do
    own_project = create(:project, group: create(:group))
    shared_project = create(:project)
    create(:project_group_link, project: shared_project, group: own_project.group)
    member = create(:user, developer_of: own_project.group)
    ProjectAuthorization.delete_all

    reached = Array.new(30) { described_class.new(100).pairs }.flatten(1).select { |user_id, _| user_id == member.id }

    expect(reached.map(&:last).uniq).to contain_exactly(own_project.id, shared_project.id)
  end

  it 'skips memberships of groups that reach no project' do
    member = create(:user, developer_of: create(:group))
    ProjectAuthorization.delete_all

    expect(pairs.map(&:first)).not_to include(member.id)
  end

  it 'returns at most about the sample size from each side' do
    expect(described_class.new(1).pairs.size).to be <= 2
  end

  context 'with a large table' do
    # A low fillfactor (undone with the test transaction) spreads a few rows over several pages, and no
    # minimum makes the sample take the large-table path.
    before do
      ProjectAuthorization.connection.execute('ALTER TABLE project_authorizations SET (fillfactor = 10)')
      users = create_list(:user, 3)
      projects = create_list(:project, 10)
      ProjectAuthorization.insert_all(projects.product(users).map do |project, user|
        { user_id: user.id, project_id: project.id, access_level: Gitlab::Access::DEVELOPER }
      end)
      stub_const("#{described_class}::SMALL_TABLE_PAGES", 0)
    end

    it 'picks rows from random pages' do
      page_of = ProjectAuthorization.pluck(:user_id, :project_id, Arel.sql('(ctid::text::point)[0]'))
        .to_h { |user_id, project_id, page| [[user_id, project_id], page] }
      expect(page_of.values.uniq.size).to be > 1

      pages = Array.new(20) do
        page_of[described_class.new(1).send(:sampled, ProjectAuthorization.all).pick(:user_id, :project_id)]
      end

      expect(pages.compact.uniq.size).to be > 1
    end

    it 'reads at most one row per page and twice the sample size in pages' do
      recorder = ActiveRecord::QueryRecorder.new { described_class.new(5).send(:sampled, ProjectAuthorization.all).to_a }

      expect(recorder.log.join).to include('generate_series(1, 10)')
      expect(described_class.new(5).send(:sampled, ProjectAuthorization.all).to_a.size).to be <= 5
    end

    it 'only samples eligible memberships' do
      requester = create(:group_member, :access_request, group: group)

      pairs = Array.new(10) { described_class.new(10).pairs }.flatten(1)

      expect(pairs.map(&:first)).not_to include(requester.user_id)
    end
  end
end
