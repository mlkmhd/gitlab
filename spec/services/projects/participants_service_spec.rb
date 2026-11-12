# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Projects::ParticipantsService, feature_category: :groups_and_projects do
  describe '#execute' do
    # Use explicit usernames to guarantee deterministic sort order.
    # project_members are sorted by the user's actual username (not the org_user_detail username),
    # so 'aaa_participant' sorts before 'zzz_org_user' ensuring a stable expected order.
    let_it_be(:user) { create(:user, username: 'aaa_participant') }
    let_it_be(:project) { create(:project, :public) }
    let_it_be(:noteable) { create(:issue, project: project) }
    let_it_be(:other_organization) { create(:organization) }
    let_it_be(:org_user_detail) do
      create(:organization_user_detail, user: create(:user, username: 'zzz_org_user'), username: 'spec_bot')
    end

    let_it_be(:other_org_user_detail) do
      create(:organization_user_detail, organization: other_organization, username: 'spec_bot')
    end

    let(:params) { {} }

    before_all do
      project.add_developer(user)
      project.add_developer(org_user_detail.user)
    end

    def run_service
      described_class.new(project, user, params).execute(noteable)
    end

    it 'returns results in correct order' do
      group = create(:group, owners: user)

      expect(run_service.pluck(:username)).to eq([
        noteable.author.username, user.username, org_user_detail.username, group.full_path
      ])
    end

    context 'when the noteable has assignees and reviewers' do
      let_it_be(:assignee_b, freeze: false) { create(:user, username: 'zzz_assignee_b', developer_of: project) }
      let_it_be(:assignee_a, freeze: false) { create(:user, username: 'zzz_assignee_a', developer_of: project) }
      let_it_be(:reviewer, freeze: false) { create(:user, username: 'zzz_reviewer', developer_of: project) }

      it 'lists issue assignees right after the author' do
        issue = create(:issue, project: project, assignees: [assignee_b, assignee_a])

        usernames = described_class.new(project, user, params).execute(issue).pluck(:username)

        expect(usernames.first(3)).to eq([issue.author.username, 'zzz_assignee_a', 'zzz_assignee_b'])
      end

      it 'lists merge request assignees, then reviewers, right after the author' do
        merge_request = create(
          :merge_request, source_project: project, assignees: [assignee_a], reviewers: [reviewer]
        )

        usernames = described_class.new(project, user, params).execute(merge_request).pluck(:username)

        expect(usernames.first(3)).to eq([merge_request.author.username, 'zzz_assignee_a', 'zzz_reviewer'])
      end

      it 'lists the author once when they are also an assignee' do
        issue = create(:issue, project: project, author: assignee_a, assignees: [assignee_a])

        usernames = described_class.new(project, user, params).execute(issue).pluck(:username)

        expect(usernames.count('zzz_assignee_a')).to eq(1)
        expect(usernames.first).to eq('zzz_assignee_a')
      end

      it 'does not return placeholder and import user assignees' do
        placeholder_user = create(:user, :placeholder)
        import_user = create(:user, :import_user)
        issue = create(:issue, project: project, assignees: [placeholder_user, import_user, assignee_a])

        usernames = described_class.new(project, user, params).execute(issue).pluck(:username)

        expect(usernames).not_to include(placeholder_user.username, import_user.username)
        expect(usernames).to include('zzz_assignee_a')
      end

      it 'does not return assignees that cannot read the project' do
        private_project = create(:project, :private, developers: [user, assignee_a])
        non_member = create(:user, username: 'aaa_non_member')
        issue = create(:issue, project: private_project, assignees: [non_member, assignee_a])

        usernames = described_class.new(private_project, user, params).execute(issue).pluck(:username)

        expect(usernames.first(2)).to eq([issue.author.username, 'zzz_assignee_a'])
      end
    end

    context 'when the mentioned param is given' do
      let_it_be(:mentioned_member) { create(:user, username: 'zzz_mentioned', developer_of: project) }
      let_it_be(:non_member) { create(:user, username: 'zzz_outsider') }

      it 'includes a mentioned project member that does not match the search' do
        params = { search: 'aaa', mentioned: [mentioned_member.username] }

        usernames = described_class.new(project, user, params).execute(noteable).pluck(:username)

        expect(usernames).to include('zzz_mentioned')
      end

      it 'does not include a mentioned username that is not a project member' do
        params = { mentioned: [non_member.username] }

        usernames = described_class.new(project, user, params).execute(noteable).pluck(:username)

        expect(usernames).not_to include('zzz_outsider')
      end

      it 'ignores over-length mentioned usernames before applying the limit (#security)' do
        oversized = Array.new(Users::ParticipableService::MENTIONED_USERS_LIMIT) do
          'a' * (Namespace::URL_MAX_LENGTH + 1)
        end
        params = { search: 'aaa', mentioned: oversized + [mentioned_member.username] }

        usernames = described_class.new(project, user, params).execute(noteable).pluck(:username)

        expect(usernames).to include('zzz_mentioned')
      end
    end

    context 'N+1 checks' do
      before do
        run_service # warmup, runs table cache queries and create queries
        BatchLoader::Executor.clear_current
      end

      it 'avoids N+1 UserDetail queries' do
        project.add_developer(create(:user))

        control = ActiveRecord::QueryRecorder.new { run_service.to_a }

        BatchLoader::Executor.clear_current

        project.add_developer(create(:user, status: build(:user_status, availability: :busy)))

        expect { run_service.to_a }.not_to exceed_query_limit(control)
      end

      it 'avoids N+1 groups queries' do
        group_1 = create(:group)
        group_1.add_owner(user)

        control = ActiveRecord::QueryRecorder.new { run_service }

        BatchLoader::Executor.clear_current

        group_2 = create(:group)
        group_2.add_owner(user)

        expect { run_service }.not_to exceed_query_limit(control)
      end

      it 'avoids N+1 OrganizationUserDetail queries' do
        developer = create(:user)
        project.add_developer(developer)
        create(
          :organization_user_detail,
          user: developer,
          username: 'test_alias',
          display_name: 'Test McAlias'
        )

        control = ActiveRecord::QueryRecorder.new { run_service.to_a }

        BatchLoader::Executor.clear_current

        developer2 = create(:user)
        project.add_developer(developer2)
        create(
          :organization_user_detail,
          user: developer2,
          username: 'test_alias2',
          display_name: 'Test McAlias2'
        )

        expect { run_service.to_a }.not_to exceed_query_limit(control)
      end
    end

    it 'does not return duplicate author' do
      participants = run_service

      expect(participants.count { |p| p[:username] == noteable.author.username }).to eq 1
    end

    it 'includes composite_identity_enforced field for users' do
      user_participants = run_service.select { |p| p[:type] == 'User' && !p[:original_username].present? }

      expect(user_participants).to all(include(:composite_identity_enforced))
    end

    describe 'role' do
      let_it_be(:mr_project) { create(:project, :repository, developers: [user]) }
      let(:author) { create(:user, developer_of: mr_project) }
      let(:assignee) { create(:user, developer_of: mr_project) }
      let(:reviewer) { create(:user, developer_of: mr_project) }
      let(:assignee_and_reviewer) { create(:user, developer_of: mr_project) }
      let(:merge_request) do
        create(:merge_request, source_project: mr_project, author: author,
          assignees: [assignee, assignee_and_reviewer, author], reviewers: [reviewer, assignee_and_reviewer])
      end

      def roles_by_username(noteable)
        described_class.new(mr_project, user, params).execute(noteable)
          .select { |p| p[:type] == 'User' }
          .to_h { |p| [p[:original_username] || p[:username], p[:role]] }
      end

      it 'returns the most relevant role of each user in the noteable' do
        expect(roles_by_username(merge_request)).to include(
          author.username => 'author',
          assignee.username => 'assignee',
          assignee_and_reviewer.username => 'assignee',
          reviewer.username => 'reviewer',
          user.username => nil
        )
      end

      it 'returns author and assignee roles for an issue, which has no reviewers' do
        issue = create(:issue, project: mr_project, author: author, assignees: [assignee])

        expect(roles_by_username(issue)).to include(author.username => 'author', assignee.username => 'assignee')
      end

      it 'returns the author role for a commit, which has no assignees or reviewers' do
        commit = mr_project.commit
        commit_author = create(:user, email: commit.author_email, developer_of: mr_project)

        expect(roles_by_username(commit)).to include(commit_author.username => 'author')
      end

      it 'returns no author role for a commit whose author is not a user' do
        expect(roles_by_username(mr_project.commit).values).not_to include('author')
      end

      it 'returns no role without a noteable' do
        expect(roles_by_username(nil).values).to all(be_nil)
      end
    end

    context 'when noteable.participants contains placeholder or import users' do
      let(:placeholder_user) { create(:user, :placeholder) }
      let(:import_user) { create(:user, :import_user) }

      it 'does not return the placeholder and import users' do
        allow(noteable).to receive(:participants).and_return([user, placeholder_user, import_user])

        participant_usernames = run_service.map { |user| user[:username] }

        expect(participant_usernames).not_to include(placeholder_user.username, import_user.username)
        expect(participant_usernames).to include(user.username)
      end
    end

    describe 'organization_user_detail items' do
      subject(:org_user_detail_items) { run_service.select { |hash| hash[:original_username].present? } }

      it 'includes items for per-organization user details within the noteable organization' do
        expect(org_user_detail_items).to include(a_hash_including(
          type: User.name,
          username: org_user_detail.username,
          name: org_user_detail.display_name,
          avatar_url: org_user_detail.user.avatar_url,
          original_username: org_user_detail.user.username,
          original_displayname: org_user_detail.user.name,
          composite_identity_enforced: org_user_detail.user.composite_identity_enforced
        ))
      end

      it 'includes the role of a user with an organization user detail' do
        issue = create(:issue, project: project, author: User.find(org_user_detail.user_id))
        items = described_class.new(project, user, params).execute(issue)

        expect(items).to include(a_hash_including(
          username: org_user_detail.username,
          original_username: org_user_detail.user.username,
          role: 'author'
        ))
      end

      it 'does not include items from other organizations' do
        expect(org_user_detail_items).not_to include(a_hash_including(
          username: other_org_user_detail.username,
          original_username: other_org_user_detail.user.username
        ))
      end

      context 'including other item types' do
        subject(:items) { run_service }

        it 'does not seprately include user for organization_user_details items' do
          matching_items = items.select do |item|
            [org_user_detail.username, org_user_detail.user.username].include?(item[:username])
          end
          expect(matching_items.count).to eq(1)
          expect(matching_items.first).to have_key(:original_username)
        end
      end
    end

    describe 'group items' do
      subject(:group_items) { run_service.select { |hash| hash[:type].eql?('Group') } }

      describe 'group user counts' do
        let(:group_1) { create(:group) }
        let(:group_2) { create(:group) }

        before do
          group_1.add_owner(user)
          group_1.add_owner(create(:user))

          group_2.add_owner(user)
          create(:group_member, :access_request, group: group_2, user: create(:user))
        end

        it 'returns correct user counts for groups' do
          expect(group_items).to contain_exactly(
            a_hash_including(name: group_1.full_name, count: 2),
            a_hash_including(name: group_2.full_name, count: 1)
          )
        end
      end

      describe 'avatar_url' do
        let(:group) { create(:group, avatar: fixture_file_upload('spec/fixtures/dk.png')) }

        before do
          group.add_owner(user)
        end

        it 'returns an url for the avatar' do
          expect(group_items.size).to eq 1
          expect(group_items.first[:avatar_url]).to eq(group.avatar_path)
        end

        it 'returns an url for the avatar with relative url' do
          stub_config_setting(relative_url_root: '/gitlab')
          stub_config_setting(url: Settings.send(:build_gitlab_url))

          expect(group_items.size).to eq 1
          expect(group_items.first[:avatar_url]).to eq(group.avatar_path)
        end
      end

      context 'with subgroups' do
        let_it_be(:group_1) { create(:group, path: 'bb', owners: user) }
        let_it_be(:group_2) { create(:group, path: 'zz', owners: user) }
        let_it_be(:subgroup) { create(:group, path: 'aa', parent: group_1, owners: user) }

        it 'returns results ordered by full path' do
          expect(group_items.pluck(:username)).to eq([
            group_1.full_path, subgroup.full_path, group_2.full_path
          ])
        end

        context 'when search param is given' do
          let(:params) { { search: 'bb' } }

          it 'only returns matching groups' do
            expect(group_items.pluck(:username)).to eq([
              group_1.full_path, subgroup.full_path
            ])
          end

          context 'when user search already returns enough results' do
            before do
              described_class::SEARCH_LIMIT.times { |i| create(:user, name: "bb#{i}", guest_of: project) }
            end

            it 'does not return any groups' do
              expect(group_items).to be_empty
            end
          end
        end
      end

      context 'when groups are in other organizations' do
        let(:group_1) { create(:group) }
        let(:group_2) { create(:group, organization: other_organization) }

        before do
          group_1.add_owner(user)
          group_1.add_owner(create(:user))

          group_2.add_owner(user)
        end

        it 'only includes groups in the projects organization' do
          expect(group_items).to contain_exactly(
            a_hash_including(name: group_1.full_name, count: 2)
          )
          expect(group_items).not_to include(
            a_hash_including(name: group_2.full_name)
          )
        end
      end
    end

    it 'does not include `All Project and Group Members`' do
      expect(run_service).not_to include(a_hash_including({ username: "all", name: "All Project and Group Members" }))
    end
  end

  describe '#project_members' do
    subject(:usernames) { service.project_members.map { |member| member[:username] } }

    context 'when there is a project in group namespace' do
      let_it_be(:public_group) { create(:group, :public) }
      let_it_be_with_reload(:public_project) { create(:project, :public, namespace: public_group) }

      let_it_be(:public_group_owner) { create(:user) }

      let(:service) { described_class.new(public_project, create(:user)) }

      before_all do
        public_group.add_owner(public_group_owner)
      end

      it 'returns members of a group' do
        expect(usernames).to include(public_group_owner.username)
      end
    end

    context 'when there is a private group and a public project' do
      let_it_be(:public_group) { create(:group, :public) }
      let_it_be(:private_group) { create(:group, :private, :nested) }
      let_it_be_with_reload(:public_project) { create(:project, :public, namespace: public_group) }

      let_it_be(:public_group_owner) { create(:user) }
      let_it_be(:private_group_member) { create(:user) }
      let_it_be(:public_project_maintainer) { create(:user) }
      let_it_be(:private_group_owner) { create(:user) }

      let_it_be(:group_ancestor_owner) { create(:user) }

      before_all do
        public_group.add_owner public_group_owner
        private_group.add_developer private_group_member
        public_project.add_maintainer public_project_maintainer

        private_group.add_owner private_group_owner
        private_group.parent.add_owner group_ancestor_owner
      end

      context 'when the private group is invited to the public project' do
        before_all do
          create(:project_group_link, group: private_group, project: public_project)
        end

        let_it_be(:current_user) { create(:user) }
        let(:service) { described_class.new(public_project, current_user) }

        it 'does not return the private group' do
          expect(usernames).not_to include(private_group.name)
        end

        it 'returns private group members' do
          expect(usernames).to include(private_group_member.username)
        end

        it 'returns the project maintainer' do
          expect(usernames).to include(public_project_maintainer.username)
        end

        it 'returns project members from an invited public group' do
          invited_public_group = create(:group, :public)
          invited_public_group.add_owner create(:user)

          create(:project_group_link, group: invited_public_group, project: public_project)

          expect(usernames).to include(invited_public_group.group_members.first.user.username)
        end

        it 'returns members of the ancestral groups of the private group' do
          expect(usernames).to include(group_ancestor_owner.username)
        end

        it 'returns invited group members of the private group' do
          invited_group = create(:group, :public)
          create(:group_group_link, shared_group: private_group, shared_with_group: invited_group)

          other_user = create(:user)
          invited_group.add_guest(other_user)

          expect(usernames).to include(other_user.username)
        end
      end
    end

    context 'when search param is given' do
      let_it_be(:project) { create(:project, :public) }
      let_it_be(:member_1) { create(:user, name: 'John Doe', guest_of: project) }
      let_it_be(:member_2) { create(:user, name: 'Jane Doe ', guest_of: project) }

      let(:service) { described_class.new(project, create(:user), search: 'johnd') }

      it 'only returns matching members' do
        expect(usernames).to eq([member_1.username])
      end
    end
  end
end
