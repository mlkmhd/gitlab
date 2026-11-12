# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Commits::RevertService, feature_category: :source_code_management do
  let(:project) { create(:project, :repository) }
  let(:repository) { project.repository }
  let(:user) { create(:user) }

  before do
    project.add_maintainer(user)
  end

  def revert(commit: project.commit, message: nil)
    described_class.new(
      project,
      user,
      commit: commit,
      start_branch: project.default_branch,
      branch_name: project.default_branch,
      message: message
    ).execute
  end

  describe '#execute' do
    it 'reverts the commit from the branch' do
      result = revert
      expect(result[:status]).to eq(:success), result[:message]

      expect(project.commit.message).to include(
        "Revert \"Merge branch 'branch-merged' into '#{project.default_branch}'\""
      )
      expect(project.commit.message).to include(
        "This reverts commit b83d6e391c22777fca1ed3012fce84f633d7fed0"
      )
    end

    it 'supports a custom commit message' do
      result = revert(message: 'revert this commit')

      expect(result[:status]).to eq(:success)
      expect(project.commit.message).to eq('revert this commit')
    end

    context 'when the commit does not exist in the target repository' do
      let(:other_project) { create(:project, :repository) }

      it 'returns an error instead of raising', :aggregate_failures do
        sha = other_project.repository.create_file(
          user, 'only-in-other-project.txt', 'content', message: 'Add file', branch_name: other_project.default_branch
        )

        result = revert(commit: other_project.commit(sha))

        expect(result[:status]).to eq(:error)
        expect(result[:message]).to eq(
          "#{s_('MergeRequests|Commit revert failed')}: " \
            "#{s_('MergeRequests|The commit could not be found in the target repository. ' \
              'Please perform this action locally.')}"
        )
      end
    end

    context 'when there is nothing to revert' do
      it 'says so' do
        commit = project.commit

        revert(commit: commit)
        result = revert(commit: commit)

        expect(result[:status]).to eq(:error)
        expect(result[:error_code]).to eq(:empty)
        expect(result[:message]).to eq(
          "#{s_('MergeRequests|Commit revert failed')}: " \
            "#{format(s_('MergeRequests|There is nothing to revert in %{branch_name}.'),
              branch_name: project.default_branch)}"
        )
      end
    end

    context 'when the revert conflicts' do
      before do
        allow(repository).to receive(:revert)
          .and_raise(Gitlab::Git::Repository::CreateTreeError, 'CONFLICT')
      end

      it 'names the branch it conflicts with' do
        result = revert

        expect(result[:status]).to eq(:error)
        expect(result[:error_code]).to eq(:conflict)
        expect(result[:message]).to eq(
          "#{s_('MergeRequests|Commit revert failed')}: " \
            "#{format(s_('MergeRequests|These changes conflict with changes on %{branch_name}. ' \
              'Revert locally to resolve the conflicts.'), branch_name: project.default_branch)}"
        )
      end
    end
  end
end
