# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'Resolving the conflicts of a merge request', feature_category: :code_review_workflow do
  include GraphqlHelpers

  let_it_be(:current_user) { create(:user) }
  let_it_be(:group) { create(:group) }

  # Not let_it_be: resolving commits to the source branch, and Gitaly changes are not rolled back
  let(:project) { create(:project, :repository, group: group, developers: current_user) }
  let(:merge_request) do
    create(:merge_request, source_project: project, source_branch: 'conflict-resolvable',
      target_branch: 'conflict-start', merge_status: :cannot_be_merged)
  end

  let(:files) do
    [
      {
        our_path: 'files/ruby/popen.rb',
        their_path: 'files/ruby/popen.rb',
        sections: [{ section_id: '2f6fcd96b88b36ce98c38da085c795a27d92a3dd_14_14', resolution: 'OURS' }]
      },
      {
        our_path: 'files/ruby/regex.rb',
        their_path: 'files/ruby/regex.rb',
        sections: [
          { section_id: '6eb14e00385d2fb284765eb1cd8d420d33d63fc9_9_9', resolution: 'OURS' },
          { section_id: '6eb14e00385d2fb284765eb1cd8d420d33d63fc9_21_21', resolution: 'THEIRS' },
          { section_id: '6eb14e00385d2fb284765eb1cd8d420d33d63fc9_49_49', resolution: 'THEIRS' }
        ]
      }
    ]
  end

  let(:mutation) do
    graphql_mutation(
      :merge_request_resolve_conflicts,
      { project_path: project.full_path, iid: merge_request.iid.to_s, files: files,
        commit_message: 'Resolve the conflicts' },
      'errors mergeRequest { id }'
    )
  end

  def mutation_response
    graphql_mutation_response(:merge_request_resolve_conflicts)
  end

  def source_head
    project.repository.commit(merge_request.source_branch)
  end

  context 'with an OAuth token with the ai_workflows scope' do
    let(:oauth_token) { create(:oauth_access_token, user: current_user, scopes: [:ai_workflows]) }

    it 'commits the resolution', :aggregate_failures do
      source_sha = source_head.sha

      post_graphql_mutation(mutation, token: { oauth_access_token: oauth_token })

      expect(mutation_response['errors']).to be_empty
      expect(source_head.parent_ids.first).to eq(source_sha)
    end
  end
end
