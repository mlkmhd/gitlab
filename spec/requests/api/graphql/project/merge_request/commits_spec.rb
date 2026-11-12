# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'Query.project(fullPath).mergeRequest(iid).commits', feature_category: :code_review_workflow do
  include GraphqlHelpers

  let_it_be(:project) { create(:project, :public, :repository) }
  let_it_be(:merge_request) { create(:merge_request, source_project: project) }
  let_it_be(:current_user) { create(:user) }

  let(:all_shas) { merge_request.commits(load_from_gitaly: true).map(&:sha) }

  def query_for(merge_request, arguments = {})
    graphql_query_for(:project, { full_path: project.full_path },
      query_graphql_field(:merge_request, { iid: merge_request.iid.to_s },
        query_graphql_field(:commits, arguments, 'pageInfo { hasNextPage endCursor } nodes { sha }')
      )
    )
  end

  def commits_data
    graphql_data_at(:project, :merge_request, :commits)
  end

  def page_through_commits
    shas = []
    after = nil

    loop do
      post_graphql(query_for(merge_request, { first: 10, after: after }.compact), current_user: current_user)
      shas.concat(commits_data['nodes'].pluck('sha'))
      break shas unless commits_data.dig('pageInfo', 'hasNextPage')

      after = commits_data.dig('pageInfo', 'endCursor')
    end
  end

  it 'pages through every commit in the stored order' do
    expect(all_shas.size).to be > 10
    expect(page_through_commits).to eq(all_shas)
  end

  it 'returns every other commit once when Gitaly is missing one in the middle of a page' do
    missing_sha = all_shas[3]
    allow(Gitlab::Git::Commit).to receive(:batch_by_oid).and_wrap_original do |original, repository, shas|
      original.call(repository, shas - [missing_sha])
    end

    expect(page_through_commits).to eq(all_shas - [missing_sha])
  end

  it 'fetches only the requested page from Gitaly' do
    first_shas = all_shas.first(2)
    allow(Gitlab::Git::Commit).to receive(:batch_by_oid).and_call_original

    post_graphql(query_for(merge_request, { first: 2 }), current_user: current_user)

    expect(Gitlab::Git::Commit).to have_received(:batch_by_oid).once
    expect(Gitlab::Git::Commit).to have_received(:batch_by_oid).with(anything, first_shas)
  end

  it 'returns the last commits with last' do
    post_graphql(query_for(merge_request, { last: 3 }), current_user: current_user)

    expect(commits_data['nodes'].pluck('sha')).to eq(all_shas.last(3))
  end

  context 'when the diff has no stored commit count' do
    before do
      MergeRequestDiff.id_in(merge_request.merge_request_diff.id).update_all(commits_count: nil)
    end

    it 'counts the commits' do
      post_graphql(query_for(merge_request, { last: 1 }), current_user: current_user)

      expect(commits_data['nodes'].pluck('sha')).to eq(all_shas.last(1))
    end
  end

  context 'when the merge request has no persisted diff' do
    let_it_be(:merge_request_without_diff) do
      create(:merge_request, :skip_diff_creation, source_project: project, source_branch: 'fix')
    end

    it 'returns no commits' do
      post_graphql(query_for(merge_request_without_diff), current_user: current_user)

      expect(graphql_errors).to be_nil
      expect(commits_data['nodes']).to be_empty
    end
  end
end
