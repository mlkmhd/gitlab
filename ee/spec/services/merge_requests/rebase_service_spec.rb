# frozen_string_literal: true

require 'spec_helper'

RSpec.describe MergeRequests::RebaseService, :request_store, feature_category: :source_code_management do
  let_it_be(:mr_author) { create(:user) }
  let_it_be(:human) { create(:user) }
  let_it_be(:service_account) { create(:user, :service_account, composite_identity_enforced: true) }
  let_it_be(:project) do
    create(:project, :repository, merge_requests_disable_committers_approval: true,
      developers: [mr_author, human, service_account])
  end

  let(:source_branch) { 'agent-change' }
  let(:merge_request) do
    create(:merge_request, author: mr_author, source_project: project, target_project: project,
      source_branch: source_branch, target_branch: 'master')
  end

  before do
    stub_licensed_features(admin_merge_request_approvers_rules: true)

    project.repository.add_branch(human, source_branch, project.commit('master').parent_id)
    # Mirrors a flow commit pushed with git: the service account authors, the human commits.
    project.repository.create_file(human, 'agent.txt', 'agent change',
      message: 'Agent change', branch_name: source_branch,
      author_email: service_account.commit_email_or_default, author_name: service_account.name)
  end

  describe '#execute' do
    context 'when a service account rebases on behalf of a human' do
      before do
        merge_request
        ::Gitlab::Auth::Identity.link_from_scoped_user(service_account, human, context: :authentication)
      end

      it 'keeps the human out of the approver pool', :aggregate_failures do
        expect(approval_state.eligible_for_approval_by?(human)).to be(false)

        result = described_class.new(project: project, current_user: human).execute(merge_request)

        expect(result).to be_success

        rebased_commit = project.repository.commit(source_branch)
        expect(rebased_commit.parent_id).to eq(project.commit('master').id)
        expect(rebased_commit.author_email).to eq(service_account.commit_email_or_default)
        expect(rebased_commit.committer_email).to eq(human.commit_email_or_default)

        merge_request.reload.reload_diff(human)

        expect(approval_state.eligible_for_approval_by?(human)).to be(false)
      end
    end
  end

  def approval_state
    ApprovalState.new(MergeRequest.find(merge_request.id))
  end
end
