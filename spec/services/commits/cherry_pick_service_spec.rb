# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Commits::CherryPickService, feature_category: :source_code_management do
  let(:project) { create(:project, :repository) }
  # *   ddd0f15 (HEAD -> master, origin/master, origin/HEAD) Merge branch 'po-fix-test-en
  # |\
  # | * 2d1db52 Correct test_env.rb path for adding branch
  # |/
  # *   1e292f8 Merge branch 'cherry-pick-ce369011' into 'master'

  let_it_be(:merge_commit_sha) { 'ddd0f15ae83993f5cb66a927a28673882e99100b' }
  let_it_be(:merge_base_sha)   { '1e292f8fedd741b75372e19097c76d327140c312' }
  let_it_be(:branch_name)      { 'stable' }

  let(:repository) { project.repository }
  let(:commit) { project.commit }
  let(:user) { create(:user, :commit_email) }

  before do
    project.add_maintainer(user)

    repository.add_branch(user, branch_name, merge_base_sha)
  end

  def cherry_pick(sha, branch_name, message: nil)
    commit = project.commit(sha)

    described_class.new(
      project,
      user,
      commit: commit,
      start_branch: branch_name,
      branch_name: branch_name,
      message: message
    ).execute
  end

  describe '#execute' do
    shared_examples 'successful cherry-pick' do
      it 'picks the commit into the branch' do
        source_commit = project.commit(merge_commit_sha)
        result = cherry_pick(merge_commit_sha, branch_name)
        expect(result[:status]).to eq(:success), result[:message]

        branch = repository.find_branch(branch_name)
        head = branch.target
        expect(head).not_to eq(merge_base_sha)

        commit = branch.dereferenced_target
        expect(commit.author_name).to eq(user.name)
        expect(commit.author_email).to eq(user.commit_email)
        expect(commit.message).to include("(cherry picked from commit #{merge_commit_sha})")
        expect(commit.message).to include(
          "Co-authored-by: #{source_commit.author_name} <#{source_commit.author_email}>"
        )
      end

      it 'supports a custom commit message' do
        result = cherry_pick(merge_commit_sha, branch_name, message: 'foo')
        branch = repository.find_branch(branch_name)

        expect(result[:status]).to eq(:success)
        expect(branch.dereferenced_target.message).to eq('foo')
      end
    end

    it_behaves_like 'successful cherry-pick'

    context 'when the changes are already in the branch' do
      it 'says so' do
        cherry_pick(merge_commit_sha, branch_name)
        result = cherry_pick(merge_commit_sha, branch_name)

        expect(result[:status]).to eq(:error)
        expect(result[:error_code]).to eq(:empty)
        expect(result[:message]).to eq(
          "#{s_('MergeRequests|Commit cherry-pick failed')}: " \
            "#{format(s_('MergeRequests|There is nothing to cherry-pick into %{branch_name}.'),
              branch_name: branch_name)}"
        )
      end
    end

    context 'when the cherry-pick conflicts' do
      before do
        allow(repository).to receive(:cherry_pick)
          .and_raise(Gitlab::Git::Repository::CreateTreeError, 'CONFLICT')
      end

      it 'names the branch it conflicts with' do
        result = cherry_pick(merge_commit_sha, branch_name)

        expect(result[:status]).to eq(:error)
        expect(result[:error_code]).to eq(:conflict)
        expect(result[:message]).to eq(
          "#{s_('MergeRequests|Commit cherry-pick failed')}: " \
            "#{format(s_('MergeRequests|These changes conflict with changes on %{branch_name}. ' \
              'Cherry-pick locally to resolve the conflicts.'), branch_name: branch_name)}"
        )
      end

      it 'names the branch picked into, not the new branch' do
        result = described_class.new(
          project,
          user,
          commit: project.commit(merge_commit_sha),
          start_branch: branch_name,
          branch_name: "cherry-pick-#{merge_commit_sha[0, 8]}"
        ).execute

        expect(result[:message]).to include(
          format(s_('MergeRequests|These changes conflict with changes on %{branch_name}. ' \
            'Cherry-pick locally to resolve the conflicts.'), branch_name: branch_name)
        )
      end
    end

    context 'when the cherry-pick fails for another reason' do
      before do
        allow(repository).to receive(:cherry_pick)
          .and_raise(Gitlab::Git::Repository::CreateTreeError, 'UNKNOWN')
      end

      it 'returns the generic message' do
        result = cherry_pick(merge_commit_sha, branch_name)

        expect(result[:message]).to eq(
          "#{s_('MergeRequests|Commit cherry-pick failed')}: " \
            "#{s_("MergeRequests|Can't perform this action automatically. " \
              'It may have already been done, or a more recent commit may have updated some of this content. ' \
              'Please perform this action locally.')}"
        )
      end
    end

    context 'when the commit email is not verified' do
      before do
        user.update_column(:commit_email, create(:email, user: user).email)
      end

      it 'authors the commit with the primary email', :aggregate_failures do
        result = cherry_pick(merge_commit_sha, branch_name)

        expect(result[:status]).to eq(:success), result[:message]
        expect(repository.find_branch(branch_name).dereferenced_target.author_email).to eq(user.email)
      end
    end

    context 'when picking a merge-request' do
      let!(:merge_request) do
        create(
          :merge_request,
          :simple,
          :merged,
          author: user,
          source_project: project,
          merge_commit_sha: merge_commit_sha
        )
      end

      it_behaves_like 'successful cherry-pick'

      it 'adds a system note' do
        result = cherry_pick(merge_commit_sha, branch_name)

        mr_notes = find_cherry_pick_notes(merge_request)
        expect(mr_notes.length).to eq(1)
        expect(mr_notes[0].commit_id).to eq(result[:result])
      end

      it 'returns a merge request specific error when the changes were already applied', :aggregate_failures do
        cherry_pick(merge_commit_sha, branch_name)
        result = cherry_pick(merge_commit_sha, branch_name)

        expect(result[:status]).to eq(:error)
        expect(result[:message]).to start_with('Merge request cherry-pick failed:')
      end
    end

    context 'when the commit does not exist in the target repository' do
      let(:other_project) { create(:project, :repository) }

      it 'returns an error instead of raising', :aggregate_failures do
        sha = other_project.repository.create_file(
          user, 'only-in-other-project.txt', 'content', message: 'Add file', branch_name: other_project.default_branch
        )

        result = described_class.new(
          project,
          user,
          commit: other_project.commit(sha),
          start_branch: branch_name,
          branch_name: branch_name
        ).execute

        expect(result[:status]).to eq(:error)
        expect(result[:message]).to eq(
          "#{s_('MergeRequests|Commit cherry-pick failed')}: " \
            "#{s_('MergeRequests|The commit could not be found in the target repository. ' \
              'Please perform this action locally.')}"
        )
      end
    end

    def find_cherry_pick_notes(noteable)
      noteable
        .notes
        .joins(:system_note_metadata)
        .where(system_note_metadata: { action: 'cherry_pick' })
    end
  end
end
