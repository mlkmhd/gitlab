# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'Pages deployments query rate limiting', feature_category: :pages do
  include GraphqlHelpers

  let_it_be(:current_user) { create(:user) }
  let_it_be(:other_user) { create(:user) }
  let_it_be(:group) { create(:group, :public) }
  let_it_be(:projects) { create_list(:project, 3, :public, group: group) }
  let_it_be(:pages_deployments) { projects.map { |project| create(:pages_deployment, project: project) } }

  before_all do
    group.add_maintainer(current_user)
    group.add_maintainer(other_user)
  end

  def project_query(project)
    graphql_query_for('project', { full_path: project.full_path }, 'pagesDeployments { nodes { id } }')
  end

  def namespace_query
    graphql_query_for('namespace', { full_path: group.full_path }, 'pagesDeployments { nodes { id } }')
  end

  # Mirrors the Usage Quotas query, which resolves pagesDeployments once for each project.
  def nested_namespace_query
    graphql_query_for(
      'namespace', { full_path: group.full_path },
      'projects { nodes { fullPath pagesDeployments { nodes { id } } } }'
    )
  end

  def nested_deployments
    graphql_data_at(:namespace, :projects, :nodes).map { |node| node['pagesDeployments'] }
  end

  def aliased_project_query
    fields = projects.first(2).each_with_index.map do |project, index|
      "p#{index}: project(fullPath: \"#{project.full_path}\") { pagesDeployments { nodes { id } } }"
    end

    "query { #{fields.join(' ')} }"
  end

  describe 'Project.pagesDeployments' do
    it_behaves_like 'rate limited endpoint', rate_limit_key: :pages_deployments_api, graphql: true do
      def request
        post_graphql(project_query(projects.first), current_user: current_user)
      end

      def request_with_second_scope
        post_graphql(project_query(projects.first), current_user: other_user)
      end
    end
  end

  describe 'Namespace.pagesDeployments' do
    it_behaves_like 'rate limited endpoint', rate_limit_key: :pages_deployments_api, graphql: true do
      def request
        post_graphql(namespace_query, current_user: current_user)
      end

      def request_with_second_scope
        post_graphql(namespace_query, current_user: other_user)
      end
    end
  end

  context 'when unauthenticated' do
    it_behaves_like 'rate limited endpoint',
      rate_limit_key: :pages_deployments_api_unauthenticated, graphql: true, use_second_scope: false do
      let(:current_user) { nil }

      def request
        post_graphql(project_query(projects.first), current_user: nil)
      end
    end
  end

  context 'with the limit applied', :clean_gitlab_redis_rate_limiting do
    before do
      stub_application_setting(pages_deployments_api_limit: 1)
    end

    it 'counts each project a namespace query resolves as one request', :aggregate_failures do
      stub_application_setting(pages_deployments_api_limit: projects.size)
      allow(Gitlab::ApplicationRateLimiter).to receive(:throttled?).and_call_original

      post_graphql(nested_namespace_query, current_user: current_user)

      expect(Gitlab::ApplicationRateLimiter).to have_received(:throttled?)
        .with(:pages_deployments_api, any_args).exactly(projects.size).times
      expect_graphql_errors_to_be_empty
      expect(nested_deployments).to all(include('nodes' => [a_hash_including('id' => be_present)]))
    end

    it 'throttles the projects resolved after the limit is reached', :aggregate_failures do
      stub_application_setting(pages_deployments_api_limit: projects.size - 1)

      post_graphql(nested_namespace_query, current_user: current_user)

      expect_graphql_errors_to_include('This endpoint has been requested too many times. Try again later.')
      expect(nested_deployments.size).to eq(projects.size)
      expect(nested_deployments.compact.size).to eq(projects.size - 1)
    end

    it 'counts each alias in a query separately', :aggregate_failures do
      post_graphql(aliased_project_query, current_user: current_user)

      expect_graphql_errors_to_include('This endpoint has been requested too many times. Try again later.')
      expect(graphql_data.values.filter_map { |project| project['pagesDeployments'] }.size).to eq(1)
    end

    it 'counts each query in a multiplexed request separately', :aggregate_failures do
      queries = Array.new(2) { { query: project_query(projects.first) } }

      post_multiplex(queries, current_user: current_user)

      expect(json_response.first['errors']).to be_nil
      expect(json_response.second['errors']).to contain_exactly(
        a_hash_including('message' => 'This endpoint has been requested too many times. Try again later.')
      )
    end

    it 'counts unauthenticated requests per IP address', :aggregate_failures do
      post_graphql(project_query(projects.first), current_user: nil)
      expect_graphql_errors_to_be_empty

      post_graphql(project_query(projects.first), current_user: nil)
      expect_graphql_errors_to_include('This endpoint has been requested too many times. Try again later.')

      post_graphql(project_query(projects.first), current_user: current_user)
      expect_graphql_errors_to_be_empty
    end
  end

  context 'when pages_deployments_api_rate_limit is disabled', :clean_gitlab_redis_rate_limiting do
    before do
      stub_feature_flags(pages_deployments_api_rate_limit: false)
      stub_application_setting(pages_deployments_api_limit: 1)
    end

    it 'does not rate limit the query' do
      3.times do
        post_graphql(project_query(projects.first), current_user: current_user)

        expect_graphql_errors_to_be_empty
      end
    end

    it 'counts the requests over the limit in log mode', :aggregate_failures do
      # RequestStore::Middleware clears the store when the request ends, so read the state while it runs.
      states = []
      allow(Gitlab::Instrumentation::RateLimitState).to receive(:track).and_wrap_original do |original, results|
        original.call(results)
        next unless results.key?('applimiter_pages_deployments_api')

        states << Gitlab::Instrumentation::RateLimitState.payload[:rate_limit_state].last
      end

      2.times do
        post_graphql(project_query(projects.first), current_user: current_user)

        expect_graphql_errors_to_be_empty
      end

      expect(states).to eq([
        'applimiter_pages_deployments_api:limit_pages_deployments_api_by_user_log:allow',
        'applimiter_pages_deployments_api:limit_pages_deployments_api_by_user_log:log'
      ])
    end
  end

  context 'when the limit is set to 0', :clean_gitlab_redis_rate_limiting do
    before do
      stub_application_setting(pages_deployments_api_limit: 0)
    end

    it 'does not rate limit the query' do
      3.times do
        post_graphql(project_query(projects.first), current_user: current_user)

        expect_graphql_errors_to_be_empty
      end
    end
  end
end
