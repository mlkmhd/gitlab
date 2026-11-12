# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'Query.project(fullPath).mergeRequest(iid).stack', feature_category: :code_review_workflow do
  include GraphqlHelpers

  let_it_be(:project) { create(:project, :repository) }
  let_it_be(:current_user) { create(:user, developer_of: project) }

  let_it_be(:merge_requests) do
    [[project.default_branch, 'feature-1'], %w[feature-1 feature-2], %w[feature-2 feature-3]]
      .map do |target_branch, source_branch|
        create(:merge_request, source_project: project, target_project: project, author: current_user,
          source_branch: source_branch, target_branch: target_branch, skip_branch_existence_check: true)
      end
  end

  let(:limit_error) do
    "\"stack\" can return at most 3 merge requests in one request, counting at least one for each field."
  end

  before do
    stub_const("#{Resolvers::MergeRequests::StackResolver}::MAX_STACK_NODES", 3)
  end

  def query_for(selection, merge_request = merge_requests[1])
    graphql_query_for(:project, { full_path: project.full_path },
      query_graphql_field(:merge_request, { iid: merge_request.iid.to_s }, selection))
  end

  it 'fits one full stack listed with the stack of every member' do
    stub_const("#{Resolvers::MergeRequests::StackResolver}::MAX_STACK_NODES", 3 * (3 + 1))

    post_graphql(query_for('stack { stack { iid } }'), current_user: current_user)

    expect(graphql_errors).to be_nil
  end

  it 'counts a stack field that finds no stack as one' do
    merge_request = create(:merge_request, source_project: project, source_branch: 'lone',
      target_branch: project.default_branch, skip_branch_existence_check: true)
    selection = (1..4).map { |i| "s#{i}: stack { iid }" }.join(' ')

    post_graphql(query_for(selection, merge_request), current_user: current_user)

    expect(graphql_errors).to include(a_hash_including('message' => limit_error))
  end

  it 'returns a stack that reaches the limit and logs how many merge requests it returned' do
    request_logs = []
    subscriber = ->(*, payload) { request_logs << payload.dig(:metadata, :graphql) }

    ActiveSupport::Notifications.subscribed(subscriber, 'process_action.action_controller') do
      post_graphql(query_for('stack { iid }'), current_user: current_user)
    end

    expect(request_logs.last).to include(a_hash_including(graphql_stack_nodes: 3))
    expect(graphql_errors).to be_nil
    expect(graphql_data_at(:project, :merge_request, :stack, :iid)).to eq(merge_requests.map { |mr| mr.iid.to_s })
  end

  where(:selection, :first_stack_path) do
    [
      ['first: stack { iid } second: stack { iid }', %w[project mergeRequest first]],
      ['stack { stack { iid } }', %w[project mergeRequest stack]]
    ]
  end

  with_them do
    it 'returns an error once the stacks add up to more than the limit, without finding more stacks' do
      allow(MergeRequests::StackFinder).to receive(:new).and_call_original
      expect(Gitlab::GraphqlLogger).to receive(:info).with(hash_including(graphql_stack_nodes: 6))

      post_graphql(query_for(selection), current_user: current_user)

      expect(graphql_errors).to include(a_hash_including('message' => limit_error))
      expect(graphql_dig_at(graphql_data, *first_stack_path)).to be_present
      expect(MergeRequests::StackFinder).to have_received(:new).twice
    end
  end

  it 'counts the queries of a multiplex together' do
    query = { query: query_for('stack { iid }') }

    post_multiplex([query, query], current_user: current_user)

    expect(json_response.first['errors']).to be_nil
    expect(json_response.first.dig('data', 'project', 'mergeRequest', 'stack').size).to eq(3)
    expect(json_response.last['errors']).to include(a_hash_including('message' => limit_error))
  end
end
