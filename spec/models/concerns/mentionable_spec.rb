# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Mentionable, feature_category: :shared do
  before do
    stub_const('Example', Class.new)
    Example.class_eval do
      include Mentionable

      attr_accessor :project, :message

      attr_mentionable :message

      def author
        nil
      end
    end
  end

  describe 'references' do
    let(:project) { build_stubbed(:project) }
    let(:mentionable) { Example.new }

    it 'excludes Jira references' do
      allow(project).to receive_messages(jira_tracker?: true)

      mentionable.project = project
      mentionable.message = 'JIRA-123'
      expect(mentionable.referenced_mentionables).to be_empty
    end
  end
end

RSpec.describe Issue, "Mentionable", feature_category: :team_planning do
  describe '#mentioned_users' do
    let_it_be(:user) { create(:user, username: 'stranger') }
    let_it_be(:user2) { create(:user, username: 'john') }
    let_it_be(:user3) { create(:user, username: 'jim') }
    let_it_be(:issue) { create(:issue, description: "#{user.to_reference} mentioned") }

    subject { issue.mentioned_users }

    it { expect(subject).to contain_exactly(user) }

    context 'when a note on personal snippet' do
      let(:note) { create(:note_on_personal_snippet, note: "#{user.to_reference} mentioned #{user3.to_reference}") }

      subject { note.mentioned_users }

      it { expect(subject).to contain_exactly(user, user3) }
    end
  end

  describe '#referenced_mentionables' do
    context 'with an issue on a private project' do
      let(:project) { create(:project, :public) }
      let(:issue) { create(:issue, project: project) }
      let(:public_issue) { create(:issue, project: project) }
      let(:private_project) { create(:project, :private) }
      let(:private_issue) { create(:issue, project: private_project) }
      let(:user) { create(:user) }

      def referenced_issues(current_user)
        issue.title = "#{private_issue.to_reference(project)} and #{public_issue.to_reference}"
        issue.referenced_mentionables(current_user)
      end

      context 'when the current user can see the issue' do
        before do
          private_project.add_developer(user)
        end

        it 'includes the reference' do
          expect(referenced_issues(user)).to contain_exactly(private_issue, public_issue)
        end
      end

      context 'when the current user cannot see the issue' do
        it 'does not include the reference' do
          expect(referenced_issues(user)).to contain_exactly(public_issue)
        end
      end

      context 'when there is no current user' do
        it 'does not include the reference' do
          expect(referenced_issues(nil)).to contain_exactly(public_issue)
        end
      end
    end
  end

  describe '#create_cross_references!' do
    let_it_be(:project) { create(:project, :small_repo) }
    let(:author)  { build(:user) }
    let(:commit)  { project.commit }
    let(:commit2) { project.commit }

    let(:issue) do
      create(:issue, project: project, description: "See #{commit.to_reference}")
    end

    it 'correctly removes already-mentioned Commits' do
      expect(SystemNoteService).not_to receive(:cross_reference)

      issue.create_cross_references!(author, [commit2])
    end
  end

  describe '#create_new_cross_references!' do
    let(:project) { create(:project) }
    let(:author)  { create(:author) }
    let(:issues)  { create_list(:issue, 2, project: project, author: author) }

    before do
      project.add_developer(author)
    end

    context 'before changes are persisted' do
      it 'ignores pre-existing references' do
        issue = create_issue(description: issues[0].to_reference)

        expect(SystemNoteService).not_to receive(:cross_reference)

        issue.description = 'New description'
        issue.create_new_cross_references!
      end

      it 'notifies new references' do
        issue = create_issue(description: issues[0].to_reference)

        expect(SystemNoteService).to receive(:cross_reference).with(issues[1], any_args)

        issue.description = issues[1].to_reference
        issue.create_new_cross_references!
      end
    end

    context 'after changes are persisted' do
      it 'ignores pre-existing references' do
        issue = create_issue(description: issues[0].to_reference)

        expect(SystemNoteService).not_to receive(:cross_reference)

        issue.update!(description: 'New description')
        issue.create_new_cross_references!
      end

      it 'notifies new references' do
        issue = create_issue(description: issues[0].to_reference)

        expect(SystemNoteService).to receive(:cross_reference).with(issues[1], any_args)

        issue.update!(description: issues[1].to_reference)
        issue.create_new_cross_references!
      end

      it 'notifies new references from project snippet note' do
        snippet = create(:project_snippet, project: project)
        note = create(:note, note: issues[0].to_reference, noteable: snippet, project: project, author: author)

        expect(SystemNoteService).to receive(:cross_reference).with(issues[1], any_args)

        note.update!(note: issues[1].to_reference)
        note.create_new_cross_references!
      end
    end

    def create_issue(description:)
      create(:issue, project: project, description: description, author: author)
    end
  end

  describe 'cross-reference limits' do
    let_it_be(:project) { create(:project) }
    let_it_be(:author) { create(:user, developer_of: project) }
    let_it_be(:targets) { create_list(:work_item, 3, project: project) }
    let_it_be(:work_item) do
      create(:work_item, project: project, author: author, description: targets.map(&:to_reference).join(' '))
    end

    before do
      stub_const('Mentionable::MAX_CROSS_REFERENCES_PER_SAVE', 2)
      allow(Gitlab::AppJsonLogger).to receive(:info)
    end

    def create_cross_references(**kwargs)
      work_item.create_cross_references!(author, [], **kwargs)
    end

    def cross_referenced_targets
      targets.select { |target| target.notes.system.exists? }
    end

    context 'when the limits are enforced' do
      it 'only checks and links the first references up to the cap' do
        expect(SystemNoteService).to receive(:cross_reference_exists?).twice.and_call_original

        create_cross_references

        expect(cross_referenced_targets).to match_array(targets.first(2))
      end

      it 'charges the budget once for each reference it checks' do
        expect(Gitlab::ApplicationRateLimiter).to receive(:throttled?)
          .with(:cross_reference_checks, scope: { user: author }, cost: 2).and_call_original

        create_cross_references
      end

      it 'skips the flags and the budget when the save has no references' do
        allow(Feature).to receive(:enabled?).and_call_original
        expect(Feature).not_to receive(:enabled?).with(:enforce_cross_reference_limits, anything)
        expect(Gitlab::ApplicationRateLimiter).not_to receive(:throttled?).with(:cross_reference_checks, anything)

        targets.first.create_cross_references!(author)
      end

      it 'logs that the cap cut the references' do
        expect(Gitlab::AppJsonLogger).to receive(:info).with(hash_including(
          message: 'Cross-reference limits exceeded',
          Labkit::Fields::CLASS_NAME => 'WorkItem',
          mentionable_id: work_item.id,
          Labkit::Fields::GL_PROJECT_ID => project.id,
          Labkit::Fields::GL_NAMESPACE_ID => project.project_namespace.id,
          Labkit::Fields::GL_USER_ID => author.id,
          references_found: 3,
          references_kept: 2,
          throttled: false,
          enforced: true
        ))

        create_cross_references
      end

      it 'logs no project or namespace for a note on a personal snippet' do
        note = create(:note_on_personal_snippet, author: author)
        allow(note).to receive(:referenced_mentionables).and_return(WorkItem.id_in(targets).to_a)

        expect(Gitlab::AppJsonLogger).to receive(:info).with(hash_including(
          Labkit::Fields::CLASS_NAME => 'Note',
          Labkit::Fields::GL_PROJECT_ID => nil,
          Labkit::Fields::GL_NAMESPACE_ID => nil
        ))

        note.create_cross_references!(author)
      end

      context 'when the author is over the budget' do
        before do
          allow(Gitlab::ApplicationRateLimiter).to receive(:throttled?).and_call_original
          allow(Gitlab::ApplicationRateLimiter).to receive(:throttled?)
            .with(:cross_reference_checks, anything).and_return(true)
        end

        it 'skips the checks and the notes, and logs it' do
          expect(SystemNoteService).not_to receive(:cross_reference_exists?)
          expect(SystemNoteService).not_to receive(:cross_reference)
          expect(Gitlab::AppJsonLogger).to receive(:info).with(hash_including(throttled: true, enforced: true))

          create_cross_references
        end
      end

      context 'with the real rate limiter', :freeze_time, :clean_gitlab_redis_rate_limiting do
        before do
          stub_application_setting(cross_reference_checks_limit: 3)
        end

        it 'counts every reference checked against the setting' do
          create_cross_references
          Note.where(noteable: targets, system: true).delete_all

          create_cross_references

          expect(cross_referenced_targets).to be_empty
        end

        it 'links a save that keeps more references than the setting allows in a fresh minute' do
          stub_application_setting(cross_reference_checks_limit: 1)

          create_cross_references

          expect(cross_referenced_targets).to match_array(targets.first(2))
        end
      end

      context 'when the budget does not apply' do
        it 'still applies the cap without charging the budget' do
          expect(Gitlab::ApplicationRateLimiter).not_to receive(:throttled?).with(:cross_reference_checks, anything)

          create_cross_references(apply_budget: false)

          expect(cross_referenced_targets).to match_array(targets.first(2))
        end
      end

      context 'with references resolved up front' do
        let(:refs) { WorkItem.id_in(targets).to_a }

        before do
          allow(work_item).to receive(:referenced_mentionables).and_return(refs)
        end

        it 'leaves out excluded references before the cap and the budget' do
          expect(Gitlab::ApplicationRateLimiter).to receive(:throttled?)
            .with(:cross_reference_checks, scope: { user: author }, cost: 2).and_call_original

          expected_ids = refs.drop(1).map(&:id)

          work_item.create_cross_references!(author, [refs.first])

          expect(cross_referenced_targets.map(&:id)).to match_array(expected_ids)
        end

        it 'still applies the cap without an author, but charges no budget' do
          expect(Gitlab::ApplicationRateLimiter).not_to receive(:throttled?).with(:cross_reference_checks, anything)
          expect(SystemNoteService).to receive(:cross_reference).twice

          work_item.create_cross_references!(nil)
        end
      end
    end

    context 'with each kind of author' do
      using RSpec::Parameterized::TableSyntax

      let_it_be(:support_bot) { create(:support_bot) }
      let_it_be(:service_user) { create(:user, user_type: :service_user) }
      let_it_be(:ai_service_account) { create(:user, :ai_service_account) }
      let_it_be(:project_bot) { create(:user, :project_bot) }
      let_it_be(:service_account) { create(:user, :service_account) }

      where(:actor, :shared) do
        ref(:support_bot)        | true
        ref(:service_user)       | true
        ref(:ai_service_account) | true
        ref(:project_bot)        | false
        ref(:service_account)    | false
      end

      with_them do
        let(:scope) { shared ? { user: actor, namespace: project.project_namespace } : { user: actor } }

        before do
          allow(work_item).to receive(:referenced_mentionables).and_return(WorkItem.id_in(targets).to_a)
        end

        it 'charges the budget per user, and per namespace for shared accounts' do
          expect(Gitlab::ApplicationRateLimiter).to receive(:throttled?)
            .with(:cross_reference_checks, scope: scope, cost: 2).and_call_original

          work_item.create_cross_references!(actor)
        end
      end

      context 'with a group-level work item' do
        let_it_be(:group) { create(:group) }
        let_it_be(:group_work_item) { create(:work_item, :group_level, namespace: group) }

        it 'charges the budget for this author and group' do
          allow(group_work_item).to receive(:referenced_mentionables).and_return(WorkItem.id_in(targets).to_a)

          expect(Gitlab::ApplicationRateLimiter).to receive(:throttled?)
            .with(:cross_reference_checks, scope: { user: support_bot, namespace: group }, cost: 2)
            .and_call_original

          group_work_item.create_cross_references!(support_bot)
        end
      end
    end

    context 'in log mode', :freeze_time, :clean_gitlab_redis_rate_limiting, :request_store do
      before do
        stub_feature_flags(enforce_cross_reference_limits: false)
        stub_application_setting(cross_reference_checks_limit: 3)
      end

      it 'records a save over the budget without skipping its references' do
        create_cross_references
        Note.where(noteable: targets, system: true).delete_all

        create_cross_references

        expect(cross_referenced_targets).to match_array(targets)
        expect(Gitlab::Instrumentation::RateLimitState.payload[:rate_limit_state]).to include(
          'applimiter_cross_reference_checks:limit_cross_reference_checks_by_user_log:log'
        )
      end
    end

    context 'with each state of the feature flag' do
      using RSpec::Parameterized::TableSyntax

      where(:enforce, :over_cap, :throttled, :linked, :log_lines) do
        false | false | false | 3 | 0
        false | true  | false | 3 | 1
        true  | false | false | 3 | 0
        true  | false | true  | 0 | 1
        true  | true  | false | 2 | 1
        true  | true  | true  | 0 | 1
      end

      with_them do
        before do
          stub_feature_flags(enforce_cross_reference_limits: enforce)
          stub_const('Mentionable::MAX_CROSS_REFERENCES_PER_SAVE', over_cap ? 2 : 3)
          allow(Gitlab::ApplicationRateLimiter).to receive(:throttled?).and_call_original
          allow(Gitlab::ApplicationRateLimiter).to receive(:throttled?)
            .with(:cross_reference_checks, anything).and_return(throttled)
        end

        it 'links, charges and logs as expected' do
          create_cross_references

          expect(cross_referenced_targets.size).to eq(linked)
          expect(Gitlab::ApplicationRateLimiter).to have_received(:throttled?)
            .with(:cross_reference_checks, anything).once
          expect(Gitlab::AppJsonLogger).to have_received(:info)
            .with(hash_including(message: 'Cross-reference limits exceeded')).exactly(log_lines).times
          expect(Gitlab::AppJsonLogger).to have_received(:info)
            .with(hash_including(throttled: throttled, enforced: enforce)).exactly(log_lines).times
        end
      end
    end

    it 'checks the feature flags for the author' do
      stub_feature_flags(enforce_cross_reference_limits: author)

      create_cross_references

      expect(cross_referenced_targets).to match_array(targets.first(2))
    end

    it 'enforces the budget for the author', :freeze_time, :clean_gitlab_redis_rate_limiting do
      stub_feature_flags(enforce_cross_reference_limits: author)
      stub_application_setting(cross_reference_checks_limit: 3)

      create_cross_references
      Note.where(noteable: targets, system: true).delete_all

      create_cross_references

      expect(cross_referenced_targets).to be_empty
    end
  end

  describe '#store_mentions!' do
    it_behaves_like 'mentions in description', :issue
    it_behaves_like 'mentions in notes', :issue do
      let(:note) { create(:note_on_issue) }
      let(:mentionable) { note.noteable }
    end
  end

  describe 'load mentions' do
    it_behaves_like 'load mentions from DB', :issue do
      let(:note) { create(:note_on_issue) }
      let(:mentionable) { note.noteable }
    end
  end
end

RSpec.describe Commit, 'Mentionable', feature_category: :source_code_management do
  let_it_be(:project) { create(:project, :public, :small_repo) }
  let(:commit) { project.commit }

  describe '#matches_cross_reference_regex?' do
    it "is false when message doesn't reference anything" do
      allow(commit.raw).to receive(:message).and_return "WIP: Do something"

      expect(commit.matches_cross_reference_regex?).to be_falsey
    end

    it 'is true if issue #number mentioned in title' do
      allow(commit.raw).to receive(:message).and_return "#1"

      expect(commit.matches_cross_reference_regex?).to be_truthy
    end

    it 'is true if references an MR' do
      allow(commit.raw).to receive(:message).and_return "See merge request !12"

      expect(commit.matches_cross_reference_regex?).to be_truthy
    end

    it 'is true if references a commit' do
      allow(commit.raw).to receive(:message).and_return "a1b2c3d4"

      expect(commit.matches_cross_reference_regex?).to be_truthy
    end

    it 'is true if issue referenced by url' do
      issue = build_stubbed(:issue, project: project)

      allow(commit.raw).to receive(:message).and_return Gitlab::UrlBuilder.build(issue)

      expect(commit.matches_cross_reference_regex?).to be_truthy
    end

    context 'with external issue tracker' do
      let_it_be(:project) { create(:project, :with_jira_integration, :small_repo) }

      it 'is true if external issues referenced' do
        allow(commit.raw).to receive(:message).and_return 'JIRA-123'

        expect(commit.matches_cross_reference_regex?).to be_truthy
      end

      it 'is true if internal issues referenced' do
        allow(commit.raw).to receive(:message).and_return '#123'

        expect(commit.matches_cross_reference_regex?).to be_truthy
      end
    end
  end

  describe '#store_mentions!' do
    it_behaves_like 'mentions in notes', :commit do
      let(:note) { create(:note_on_commit) }
      let(:mentionable) { note.noteable }
    end

    context 'with sharding_key trigger' do
      let_it_be(:user) { create(:user) }
      let_it_be(:project) { create(:project, :public, :small_repo) }
      let_it_be(:commit) { project.commit }

      let(:note) { create(:note_on_commit, commit_id: commit.id, project: project) }
      let(:note_desc) { user.to_reference }
      let(:mentionable) { note.noteable }

      context 'with user mention creation' do
        it 'syncs value with notes column namespace_id' do
          note.update!(note: note_desc)
          # Set namespace_id after the save: ensure_namespace_id clears it for a
          # project-scoped note, so update_column reinstates the dual-key state
          # this example exercises without re-triggering the callback.
          note.update_column(:namespace_id, project.project_namespace_id)
          # delete user mentions created when saving the note
          mentionable.user_mentions.delete_all

          expect { note.store_mentions! }.to change { mentionable.user_mentions.count }.by(1)
          expect(mentionable.user_mentions.last.namespace_id).to eq(note.namespace_id)
        end

        it 'syncs value with notes project namespace' do
          note.update!(note: note_desc)
          mentionable.user_mentions.delete_all

          expect(note.namespace_id).to be_nil

          expect { note.store_mentions! }.to change { mentionable.user_mentions.count }.by(1)
          expect(mentionable.user_mentions.last.namespace_id).to eq(note.project.project_namespace_id)
        end
      end

      context 'with user mention update' do
        let(:note) { create(:note_on_commit, commit_id: commit.id, project: project) }

        it 'syncs value with notes column namespace_id' do
          note.update!(note: note_desc)
          # See note above: reinstate namespace_id after the callback clears it.
          note.update_column(:namespace_id, project.project_namespace_id)
          mentionable.user_mentions.last.update_column(:namespace_id, nil)

          # updates user mention created when saving the note
          expect { note.store_mentions! }.not_to change { mentionable.user_mentions.count }

          expect(mentionable.user_mentions.count).to eq 1
          expect(mentionable.user_mentions.last.reload.namespace_id).to eq(note.namespace_id)
        end

        it 'syncs value with notes column project_id' do
          note.update!(note: note_desc)
          mentionable.user_mentions.last.update_column(:namespace_id, nil)

          expect(note.namespace_id).to be_nil

          expect { note.store_mentions! }.not_to change { mentionable.user_mentions.count }

          expect(mentionable.user_mentions.count).to eq 1
          expect(mentionable.user_mentions.last.reload.namespace_id).to eq(note.project.project_namespace_id)
        end
      end
    end
  end

  describe 'load mentions' do
    it_behaves_like 'load mentions from DB', :commit do
      let(:note) { create(:note_on_commit) }
      let(:mentionable) { note.noteable }
    end
  end
end

RSpec.describe MergeRequest, 'Mentionable', feature_category: :code_review_workflow do
  describe '#store_mentions!' do
    it_behaves_like 'mentions in description', :merge_request
    it_behaves_like 'mentions in notes', :merge_request do
      let(:project) { create(:project) }
      let(:merge_request) { create(:merge_request, source_project: project, target_project: project) }
      let(:note) { create(:note_on_merge_request, noteable: merge_request, project: merge_request.project) }
      let(:mentionable) { note.noteable }
    end
  end

  describe 'load mentions' do
    it_behaves_like 'load mentions from DB', :merge_request do
      let(:project) { create(:project) }
      let(:merge_request) { create(:merge_request, source_project: project, target_project: project) }
      let(:note) { create(:note_on_merge_request, noteable: merge_request, project: merge_request.project) }
      let(:mentionable) { note.noteable }
    end
  end
end

RSpec.describe Snippet, 'Mentionable', feature_category: :source_code_management do
  describe '#store_mentions!' do
    it_behaves_like 'mentions in description', :project_snippet
    it_behaves_like 'mentions in notes', :project_snippet do
      let(:note) { create(:note_on_project_snippet) }
      let(:mentionable) { note.noteable }
    end
  end

  describe 'load mentions' do
    it_behaves_like 'load mentions from DB', :project_snippet do
      let(:note) { create(:note_on_project_snippet) }
      let(:mentionable) { note.noteable }
    end
  end
end

RSpec.describe PersonalSnippet, 'Mentionable', feature_category: :source_code_management do
  describe '#store_mentions!' do
    it_behaves_like 'mentions in description', :personal_snippet
    it_behaves_like 'mentions in notes', :personal_snippet do
      let(:note) { create(:note_on_personal_snippet) }
      let(:mentionable) { note.noteable }
    end
  end

  describe 'load mentions' do
    it_behaves_like 'load mentions from DB', :personal_snippet do
      let(:note) { create(:note_on_personal_snippet) }
      let(:mentionable) { note.noteable }
    end
  end
end

RSpec.describe DesignManagement::Design, feature_category: :team_planning do
  describe '#store_mentions!' do
    it_behaves_like 'mentions in notes', :design do
      let(:note) { create(:diff_note_on_design) }
      let(:mentionable) { note.noteable }
    end
  end

  describe 'load mentions' do
    it_behaves_like 'load mentions from DB', :design do
      let(:note) { create(:diff_note_on_design) }
      let(:mentionable) { note.noteable }
    end
  end
end
