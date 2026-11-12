# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Projects::Members::EffectiveAccessLevelPerUserFinder, '#execute' do
  let_it_be(:group) { create(:group) }
  let_it_be(:project) { create(:project, group: group) }
  let_it_be(:user) { create(:user) }

  subject(:effective_access_levels) { described_class.new(project, user).execute }

  context 'a combination of all possible avenues of membership' do
    let_it_be(:another_user) { create(:user) }
    let_it_be(:unlisted_user) { create(:user) }
    let_it_be(:shared_with_group) { create(:group) }

    before_all do
      create(:project_group_link, :maintainer, project: project, group: shared_with_group)
      create(:group_group_link, :reporter, shared_group: project.group, shared_with_group: shared_with_group)

      shared_with_group.add_maintainer(user)
      shared_with_group.add_maintainer(another_user)
      group.add_guest(user)
      group.add_guest(another_user)
      project.add_developer(user)
      project.add_developer(another_user)
      project.add_developer(unlisted_user)
    end

    it 'includes the highest access level from all avenues of memberships for the specific user alone' do
      # MAINTAINER comes from the project_group_link
      expect(effective_access_levels).to contain_exactly([user.id, Gitlab::Access::MAINTAINER])
    end

    it 'takes a list of users or user IDs' do
      expect(described_class.new(project, [user, another_user.id]).execute)
        .to contain_exactly([user.id, Gitlab::Access::MAINTAINER], [another_user.id, Gitlab::Access::MAINTAINER])
    end
  end

  it 'returns nothing without querying when given no users' do
    finder = described_class.new(project, [])

    expect(ActiveRecord::QueryRecorder.new { expect(finder.execute).to eq([]) }.count).to eq(0)
  end
end
