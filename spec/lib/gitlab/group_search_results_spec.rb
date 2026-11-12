# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Gitlab::GroupSearchResults, feature_category: :global_search do
  # group creation calls GroupFinder, so need to create the group
  # before so expect(GroupsFinder) check works
  let_it_be_with_reload(:group) { create(:group) }
  let_it_be(:user) { create(:user) }
  let_it_be(:project) { create(:project, :public, group: group) }

  let(:filters) { {} }
  let(:limit_projects) { Project.all }
  let(:query) { 'gob' }

  subject(:results) { described_class.new(user, query, limit_projects, group: group, filters: filters) }

  describe 'issues search' do
    let_it_be(:opened_result) { create(:issue, :opened, project: project, title: 'foo opened') }
    let_it_be(:closed_result) { create(:issue, :closed, project: project, title: 'foo closed') }
    let_it_be(:confidential_result) { create(:issue, :confidential, project: project, title: 'foo confidential') }

    let(:query) { 'foo' }
    let(:scope) { 'issues' }

    before_all do
      project.add_developer(user)
    end

    include_examples 'search results filtered by state'
    include_examples 'search results filtered by confidential'
  end

  describe 'merge_requests search' do
    let_it_be(:unarchived_project) { create(:project, :public, group: group) }
    let_it_be(:archived_project) { create(:project, :public, :archived, group: group) }
    let(:opened_result) { create(:merge_request, :opened, source_project: project, title: 'foo opened') }
    let(:closed_result) { create(:merge_request, :closed, source_project: project, title: 'foo closed') }
    let_it_be(:unarchived_result) { create(:merge_request, source_project: unarchived_project, title: 'foo') }
    let_it_be(:archived_result) { create(:merge_request, source_project: archived_project, title: 'foo') }
    let(:query) { 'foo' }
    let(:scope) { 'merge_requests' }

    before do
      # we're creating those instances in before block because otherwise factory for MRs will fail on after(:build)
      opened_result
      closed_result
    end

    include_examples 'search results filtered by state'
    include_examples 'search results filtered by archived'
  end

  describe 'milestones search' do
    let_it_be(:unarchived_project) { create(:project, :public, group: group) }
    let_it_be(:archived_project) { create(:project, :public, :archived, group: group) }
    let_it_be(:unarchived_result) { create(:milestone, project: unarchived_project, title: 'foo') }
    let_it_be(:archived_result) { create(:milestone, project: archived_project, title: 'foo') }
    let(:query) { 'foo' }
    let(:scope) { 'milestones' }

    include_examples 'search results filtered by archived'

    context 'when user cannot read milestones on the group' do
      let_it_be(:private_group) { create(:group, :private) }
      let_it_be(:private_project) { create(:project, :private, group: private_group) }
      let_it_be(:milestone) { create(:milestone, project: private_project, title: 'foo secret') }
      let(:query) { 'foo' }
      let(:limit_projects) do
        projects = ::ProjectsFinder.new(current_user: user).execute.preload(:topics, :project_topics, :route)
        projects.for_group_and_its_subgroups(private_group)
      end

      it 'returns no milestones' do
        results = described_class.new(user, query, limit_projects, group: private_group, filters: filters)

        expect(results.objects('milestones')).to be_empty
      end
    end

    context 'with group milestones' do
      let_it_be(:group_milestone) { create(:milestone, group: group, title: 'foo group milestone') }
      let(:query) { 'foo' }

      it 'includes group milestones in search results' do
        expect(results.objects('milestones')).to include(group_milestone)
      end

      it 'includes both project and group milestones' do
        objects = results.objects('milestones')

        expect(objects).to include(unarchived_result, group_milestone)
      end

      it 'preloads the parent and its route to avoid N+1 queries' do
        objects = results.objects('milestones', preload_method: :with_web_entity_associations).to_a
        milestone = objects.find { |m| m.id == group_milestone.id }

        expect(milestone.association(:group)).to be_loaded
        expect(milestone.group.association(:route)).to be_loaded
      end
    end

    context 'with milestones across the group hierarchy' do
      let_it_be(:parent_group) { create(:group, :public) }
      let_it_be(:searched_group) { create(:group, :public, parent: parent_group) }
      let_it_be(:subgroup) { create(:group, :public, parent: searched_group) }
      let_it_be(:searched_group_project) { create(:project, :public, group: searched_group) }
      let_it_be(:subgroup_project) { create(:project, :public, group: subgroup) }
      let_it_be(:parent_milestone) { create(:milestone, group: parent_group, title: 'foo parent') }
      let_it_be(:searched_group_milestone) { create(:milestone, group: searched_group, title: 'foo searched') }
      let_it_be(:subgroup_milestone) { create(:milestone, group: subgroup, title: 'foo subgroup') }
      let_it_be(:project_milestone) { create(:milestone, project: searched_group_project, title: 'foo project') }
      let_it_be(:subgroup_project_milestone) do
        create(:milestone, project: subgroup_project, title: 'foo subgroup project')
      end

      let(:query) { 'foo' }
      let(:limit_projects) { Project.for_group_and_its_subgroups(searched_group) }

      subject(:results) { described_class.new(user, query, limit_projects, group: searched_group, filters: filters) }

      it 'includes milestones of the group, its ancestors, its subgroups and their projects' do
        expect(results.objects('milestones')).to contain_exactly(
          parent_milestone, searched_group_milestone, subgroup_milestone, project_milestone, subgroup_project_milestone
        )
      end
    end

    context 'with private groups across the hierarchy' do
      let_it_be(:member) { create(:user) }
      let_it_be(:parent_group) { create(:group, :private) }
      let_it_be(:searched_group) { create(:group, :private, parent: parent_group) }
      let_it_be(:subgroup) { create(:group, :private, parent: searched_group) }
      let_it_be(:archived_subgroup) { create(:group, :private, :archived, parent: searched_group) }
      let_it_be(:parent_milestone) { create(:milestone, group: parent_group, title: 'foo parent') }
      let_it_be(:searched_group_milestone) { create(:milestone, group: searched_group, title: 'foo searched') }
      let_it_be(:subgroup_milestone) { create(:milestone, group: subgroup, title: 'foo subgroup') }
      let_it_be(:archived_milestone) { create(:milestone, group: archived_subgroup, title: 'foo archived') }

      let(:query) { 'foo' }

      subject(:milestones) do
        described_class.new(member, query, Project.none, group: searched_group, filters: filters).objects('milestones')
      end

      context 'when the user is a member of the searched group' do
        before_all do
          searched_group.add_guest(member)
        end

        it 'includes the group and its subgroups, but not the private parent' do
          expect(milestones).to contain_exactly(searched_group_milestone, subgroup_milestone)
        end

        context 'when including archived' do
          let(:filters) { { include_archived: true } }

          it 'also includes archived subgroups' do
            expect(milestones).to contain_exactly(searched_group_milestone, subgroup_milestone, archived_milestone)
          end
        end
      end

      context 'when the user is a member of the parent group' do
        before_all do
          parent_group.add_guest(member)
        end

        it 'includes the whole hierarchy except archived subgroups' do
          expect(milestones).to contain_exactly(parent_milestone, searched_group_milestone, subgroup_milestone)
        end
      end

      context 'when the user is a member of a subgroup only' do
        before_all do
          subgroup.add_guest(member)
        end

        it 'includes only that subgroup' do
          expect(milestones).to contain_exactly(subgroup_milestone)
        end
      end

      context 'when the user is a member of a project in a subgroup only' do
        before_all do
          create(:project, :private, group: subgroup, reporters: member)
        end

        it "includes the project's group and its ancestors" do
          expect(milestones).to contain_exactly(parent_milestone, searched_group_milestone, subgroup_milestone)
        end
      end

      context 'when a subgroup is shared with a group the user is a member of' do
        before_all do
          create(:group_group_link, shared_group: subgroup, shared_with_group: create(:group, guests: member))
        end

        it 'includes that subgroup only' do
          expect(milestones).to contain_exactly(subgroup_milestone)
        end
      end
    end

    context 'when the user is not signed in' do
      let_it_be(:public_parent) { create(:group, :public) }
      let_it_be(:public_searched_group) { create(:group, :public, parent: public_parent) }
      let_it_be(:public_subgroup) { create(:group, :public, parent: public_searched_group) }
      let_it_be(:private_subgroup) { create(:group, :private, parent: public_searched_group) }
      let_it_be(:public_parent_milestone) { create(:milestone, group: public_parent, title: 'foo parent') }
      let_it_be(:public_searched_milestone) { create(:milestone, group: public_searched_group, title: 'foo searched') }
      let_it_be(:public_subgroup_milestone) { create(:milestone, group: public_subgroup, title: 'foo subgroup') }
      let_it_be(:private_subgroup_milestone) { create(:milestone, group: private_subgroup, title: 'foo private') }

      let(:query) { 'foo' }

      subject(:milestones) do
        described_class.new(nil, query, Project.none, group: public_searched_group, filters: filters)
          .objects('milestones')
      end

      it 'includes only public groups in the hierarchy' do
        expect(milestones).to contain_exactly(
          public_parent_milestone, public_searched_milestone, public_subgroup_milestone
        )
      end
    end

    context 'when a member searches a top-level group' do
      let_it_be(:member) { create(:user) }
      let_it_be(:top_level_group) { create(:group, :private, guests: member) }
      let_it_be(:top_level_subgroup) { create(:group, :private, parent: top_level_group) }
      let_it_be(:other_group) { create(:group, :private, guests: member) }
      let_it_be(:top_level_milestone) { create(:milestone, group: top_level_group, title: 'foo top level') }
      let_it_be(:top_level_subgroup_milestone) do
        create(:milestone, group: top_level_subgroup, title: 'foo top level subgroup')
      end

      let_it_be(:other_milestone) { create(:milestone, group: other_group, title: 'foo other') }

      let(:query) { 'foo' }

      subject(:milestones) do
        described_class.new(member, query, Project.none, group: top_level_group, filters: filters).objects('milestones')
      end

      it 'includes only the group and its subgroups' do
        expect(milestones).to contain_exactly(top_level_milestone, top_level_subgroup_milestone)
      end
    end

    # Fails if a new way of granting group access reaches `public_or_visible_to_user` but not milestone search.
    context 'when compared with self_and_hierarchy.public_or_visible_to_user' do
      using RSpec::Parameterized::TableSyntax

      let_it_be(:parent_group) { create(:group, :public) }
      let_it_be(:searched_group) { create(:group, :internal, parent: parent_group) }
      let_it_be(:internal_subgroup) { create(:group, :internal, parent: searched_group) }
      let_it_be(:private_subgroup) { create(:group, :private, parent: searched_group) }
      let_it_be(:shared_subgroup) { create(:group, :private, parent: searched_group) }
      let_it_be(:project_subgroup) { create(:group, :private, parent: searched_group) }
      let_it_be(:milestones_by_group) do
        [parent_group, searched_group, internal_subgroup, private_subgroup, shared_subgroup, project_subgroup]
          .index_with do |milestone_group|
            create(:milestone, group: milestone_group, title: "foo #{milestone_group.path}")
          end
      end

      let_it_be(:non_member) { create(:user) }
      let_it_be(:parent_member) { create(:user) }
      let_it_be(:searched_group_member) { create(:user) }
      let_it_be(:subgroup_member) { create(:user) }
      let_it_be(:project_member) { create(:user) }
      let_it_be(:shared_group_member) { create(:user) }

      before_all do
        parent_group.add_guest(parent_member)
        searched_group.add_guest(searched_group_member)
        private_subgroup.add_guest(subgroup_member)
        create(:project, :private, group: project_subgroup, reporters: project_member)
        create(:group_group_link, shared_group: shared_subgroup,
          shared_with_group: create(:group, guests: shared_group_member))
      end

      where(:case_name, :current_user) do
        'anonymous'                                   | nil
        'non-member'                                  | ref(:non_member)
        'member of the parent group'                  | ref(:parent_member)
        'member of the searched group'                | ref(:searched_group_member)
        'member of a private subgroup'                | ref(:subgroup_member)
        'member of a project in a subgroup'           | ref(:project_member)
        'member of a group a subgroup is shared with' | ref(:shared_group_member)
      end

      with_them do
        it 'returns milestones of the same groups' do
          visible_groups = searched_group.self_and_hierarchy.public_or_visible_to_user(current_user)
          milestones = described_class.new(current_user, 'foo', Project.none, group: searched_group)
                                      .objects('milestones')

          expect(milestones).to match_array(milestones_by_group.values_at(*visible_groups))
        end
      end
    end

    context 'with project issue and merge request access levels' do
      let_it_be(:features_group) { create(:group, :public) }
      let_it_be(:issues_only) { create(:project, :public, :merge_requests_disabled, group: features_group) }
      let_it_be(:merge_requests_only) { create(:project, :public, :issues_disabled, group: features_group) }
      let_it_be(:both_disabled) do
        create(:project, :public, :issues_disabled, :merge_requests_disabled, group: features_group)
      end

      let_it_be(:both_private) do
        create(:project, :public, :issues_private, :merge_requests_private, group: features_group)
      end

      let_it_be(:issues_only_milestone) { create(:milestone, project: issues_only, title: 'foo issues') }
      let_it_be(:merge_requests_only_milestone) do
        create(:milestone, project: merge_requests_only, title: 'foo merge requests')
      end

      let_it_be(:both_disabled_milestone) { create(:milestone, project: both_disabled, title: 'foo disabled') }
      let_it_be(:both_private_milestone) { create(:milestone, project: both_private, title: 'foo private') }

      let(:query) { 'foo' }

      subject(:milestones) do
        described_class.new(user, query, Project.for_group_and_its_subgroups(features_group), group: features_group,
          filters: filters).objects('milestones')
      end

      it 'includes projects with issues or merge requests available to the user' do
        expect(milestones).to contain_exactly(issues_only_milestone, merge_requests_only_milestone)
      end

      context 'when the user is a member of the project with private features' do
        before_all do
          both_private.add_reporter(user)
        end

        it 'also includes that project' do
          expect(milestones).to contain_exactly(
            issues_only_milestone, merge_requests_only_milestone, both_private_milestone
          )
        end
      end
    end
  end

  describe '#projects' do
    let(:scope) { 'projects' }
    let(:query) { 'Test' }

    describe 'filtering' do
      let_it_be_with_reload(:group) { create(:group) }
      let_it_be(:unarchived_result) { create(:project, :public, group: group, name: 'Test1') }
      let_it_be(:archived_result) { create(:project, :archived, :public, group: group, name: 'Test2') }

      it_behaves_like 'search results filtered by archived'
    end
  end

  describe 'user search' do
    subject(:objects) { results.objects('users') }

    it 'returns the users belonging to the group matching the search query' do
      user1 = create(:user, username: 'gob_bluth')
      create(:group_member, :developer, user: user1, group: group)

      user2 = create(:user, username: 'michael_bluth')
      create(:group_member, :developer, user: user2, group: group)

      create(:user, username: 'gob_2018')

      is_expected.to eq [user1]
    end

    it 'returns the user belonging to the subgroup matching the search query' do
      user1 = create(:user, username: 'gob_bluth')
      subgroup = create(:group, parent: group)
      create(:group_member, :developer, user: user1, group: subgroup)

      create(:user, username: 'gob_2018')

      is_expected.to eq [user1]
    end

    it 'returns the user belonging to the parent group matching the search query' do
      user1 = create(:user, username: 'gob_bluth')
      parent_group = create(:group, children: [group])
      create(:group_member, :developer, user: user1, group: parent_group)

      create(:user, username: 'gob_2018')

      is_expected.to eq [user1]
    end

    it 'does not return the user belonging to the private subgroup' do
      user1 = create(:user, username: 'gob_bluth')
      subgroup = create(:group, :private, parent: group)
      create(:group_member, :developer, user: user1, group: subgroup)

      create(:user, username: 'gob_2018')

      is_expected.to be_empty
    end

    it 'does not return the user belonging to an unrelated group' do
      user = create(:user, username: 'gob_bluth')
      unrelated_group = create(:group)
      create(:group_member, :developer, user: user, group: unrelated_group)

      is_expected.to be_empty
    end

    it 'does not return the user invited to the group' do
      user = create(:user, username: 'gob_bluth')
      create(:group_member, :invited, :developer, user: user, group: group)

      is_expected.to be_empty
    end

    it 'calls GroupFinder during execution' do
      expect(GroupsFinder).to receive(:new).with(user).and_call_original

      objects
    end

    context 'when private project member searches for user in private group' do
      let_it_be(:private_group) { create(:group, :private) }
      let_it_be(:private_project) { create(:project, :private, group: private_group) }
      let_it_be(:user2) { create(:user, username: 'gob_bluth') }

      let(:private_results) { described_class.new(user, query, limit_projects, group: private_group, filters: filters) }

      before_all do
        private_group.add_guest(user2)
        private_project.add_guest(user)
      end

      it 'returns empty when user does not have read_group_member permission' do
        expect(private_results.objects('users')).to be_empty
      end
    end
  end

  describe "#issuable_params" do
    it 'sets include_subgroups flag by default' do
      expect(results.issuable_params[:include_subgroups]).to be(true)
    end
  end

  describe '#work_items', unless: Gitlab.ee? do
    it 'returns issues when searching for work items' do
      issue = create(:issue, project: project, title: 'test issue')
      project.add_developer(user)

      results_query = described_class.new(user, 'test', limit_projects, group: group)
      work_items_results = results_query.work_items

      expect(work_items_results).to include(issue)
    end

    it 'passes finder params to underlying issues search' do
      closed_issue = create(:issue, :closed, project: project, title: 'test closed')
      opened_issue = create(:issue, :opened, project: project, title: 'test opened')
      project.add_developer(user)

      results_query = described_class.new(user, 'test', limit_projects, group: group)
      work_items_results = results_query.work_items(state: 'closed')

      expect(work_items_results).to include(closed_issue)
      expect(work_items_results).not_to include(opened_issue)
    end

    context 'when filtering by work_item_type_ids' do
      let(:task_type) { build(:work_item_system_defined_type, :task) }

      let_it_be(:task_work_item) { create(:work_item, :task, project: project, title: 'test task') }
      let_it_be(:issue_work_item) { create(:work_item, project: project, title: 'test issue wi') }

      before_all do
        project.add_developer(user)
      end

      it 'filters by work_item_type_ids when present in filters' do
        filtered_results = described_class.new(
          user, 'test', limit_projects, group: group,
          filters: { work_item_type_ids: [task_type.id] }
        )

        expect(filtered_results.objects('work_items')).to include(task_work_item)
        expect(filtered_results.objects('work_items')).not_to include(issue_work_item)
      end

      it 'returns all work items when work_item_type_ids filter is empty' do
        filtered_results = described_class.new(
          user, 'test', limit_projects, group: group,
          filters: {}
        )

        expect(filtered_results.objects('work_items')).to include(task_work_item, issue_work_item)
      end
    end
  end
end
