# frozen_string_literal: true

require 'spec_helper'

RSpec.describe GraphqlChannel, feature_category: :api do
  let_it_be(:merge_request) { create(:merge_request) }
  let_it_be(:user) { create(:user, developer_of: merge_request.project) }
  let_it_be(:read_api_token) { create(:personal_access_token, scopes: ['read_api'], user: user) }
  let_it_be(:read_user_token) { create(:personal_access_token, scopes: ['read_user'], user: user) }
  let_it_be(:read_api_and_read_user_token) do
    create(:personal_access_token, scopes: %w[read_user read_api], user: user)
  end

  let_it_be(:expired_token) { create(:personal_access_token, :expired, scopes: %w[read_api], user: user) }
  let_it_be(:revoked_token) { create(:personal_access_token, :revoked, scopes: %w[read_api], user: user) }

  describe '#subscribed' do
    let(:query) do
      <<~GRAPHQL
      subscription mergeRequestReviewersUpdated($issuableId: IssuableID!) {
        mergeRequestReviewersUpdated(issuableId: $issuableId) {
          ... on MergeRequest { id title }
        }
      }
      GRAPHQL
    end

    let(:subscribe_params) do
      {
        query: query,
        variables: { issuableId: merge_request.to_global_id }
      }
    end

    before do
      stub_action_cable_connection current_user: user
    end

    it 'subscribes to the given graphql subscription' do
      subscribe(subscribe_params)

      expect(subscription).to be_confirmed
      expect(subscription.streams).to include(/graphql-event::mergeRequestReviewersUpdated:issuableId/)
    end

    it 'does not transmit the empty result of the initial execution' do
      subscribe(subscribe_params)

      expect(subscription).to be_confirmed
      expect(transmissions).to be_empty
    end

    context 'when the subscription returns initial data' do
      before do
        allow_next_instance_of(Subscriptions::IssuableUpdated) do |instance|
          allow(instance).to receive(:subscribe).and_return(merge_request)
        end
      end

      it 'transmits the initial data' do
        subscribe(subscribe_params)

        expect(transmissions).to contain_exactly(
          a_hash_including(
            'result' => {
              'data' => { 'mergeRequestReviewersUpdated' => a_hash_including('title' => merge_request.title) }
            },
            'more' => true
          )
        )
      end
    end

    context 'when the subscription is unauthorized' do
      before do
        stub_action_cable_connection current_user: create(:user)
      end

      it 'transmits the errors' do
        subscribe(subscribe_params)

        expect(transmissions).to contain_exactly(
          a_hash_including(
            'result' => a_hash_including('errors' => [a_hash_including('message' => 'Unauthorized subscription')]),
            'more' => true
          )
        )
      end
    end

    context 'with a personal access token' do
      let(:app_context) { Gitlab::ApplicationContext.current }

      before do
        stub_action_cable_connection current_user: user, access_token: access_token
      end

      context 'with an api scoped personal access token' do
        let(:access_token) { read_api_token }

        it 'subscribes to the given graphql subscription' do
          subscribe(subscribe_params)

          expect(subscription).to be_confirmed
          expect(subscription.streams).to include(/graphql-event::mergeRequestReviewersUpdated:issuableId/)
          expect(app_context.keys).not_to include('meta.auth_fail_reason', 'meta.auth_fail_token_id')
        end
      end

      context 'with a read_user personal access token' do
        let(:access_token) { read_user_token }

        it 'does not subscribe to the given graphql subscription' do
          subscribe(subscribe_params)

          expect(subscription).not_to be_confirmed
          expect(app_context['meta.auth_fail_reason']).to eq('insufficient_scope')
          expect(app_context['meta.auth_fail_token_id']).to eq("PersonalAccessToken/#{access_token.id}")
        end
      end

      context 'with a read_api and read_user personal access token' do
        let(:access_token) { read_api_and_read_user_token }

        it 'subscribes to the given graphql subscription' do
          subscribe(subscribe_params)

          expect(subscription).to be_confirmed
          expect(subscription.streams).to include(/graphql-event::mergeRequestReviewersUpdated:issuableId/)
          expect(app_context.keys).not_to include('meta.auth_fail_reason', 'meta.auth_fail_token_id')
        end
      end

      context 'with an expired read_user personal access token' do
        let(:access_token) { expired_token }

        it 'does not subscribe to the given graphql subscription' do
          subscribe(subscribe_params)

          expect(subscription).not_to be_confirmed
          expect(app_context['meta.auth_fail_reason']).to eq('token_expired')
          expect(app_context['meta.auth_fail_token_id']).to eq("PersonalAccessToken/#{access_token.id}")
        end
      end

      context 'with a revoked read_user personal access token' do
        let(:access_token) { revoked_token }

        it 'does not subscribe to the given graphql subscription' do
          subscribe(subscribe_params)

          expect(subscription).not_to be_confirmed
          expect(app_context['meta.auth_fail_reason']).to eq('token_revoked')
          expect(app_context['meta.auth_fail_token_id']).to eq("PersonalAccessToken/#{access_token.id}")
        end
      end
    end

    describe 'metrics' do
      before do
        stub_action_cable_connection current_user: create(:user)
      end

      it 'does not track unauthorized subscriptions as errors' do
        expect(Gitlab::Metrics::RailsSlis.graphql_query_apdex).not_to receive(:increment)

        expect(Gitlab::Metrics::RailsSlis.graphql_query_error_rate).to receive(:increment).with({
          labels: anything,
          error: false
        })

        subscribe(subscribe_params)

        expect(transmissions.first['result']).to match(a_hash_including(
          'errors' => [
            a_hash_including(
              'message' => 'Unauthorized subscription'
            )
          ]
        ))
      end
    end

    describe 'context' do
      let_it_be(:organization) { create(:organization) }
      let(:graphql_result) do
        instance_double(GraphQL::Query::Result, to_h: {}, subscription?: false, context: {})
      end

      before do
        stub_action_cable_connection current_organization: organization
      end

      it 'includes current_organization context' do
        expect(GitlabSchema).to receive(:execute).with(
          anything,
          hash_including(
            context: hash_including(current_organization: organization)
          )
        ).and_return(graphql_result)

        subscribe(subscribe_params)
      end

      context 'when authenticated with an access token' do
        before do
          stub_action_cable_connection current_user: user, access_token: read_api_token
        end

        it 'includes the access token so granular authorization is enforced' do
          expect(GitlabSchema).to receive(:execute).with(
            anything,
            hash_including(
              context: hash_including(access_token: read_api_token)
            )
          ).and_return(graphql_result)

          subscribe(subscribe_params)
        end
      end

      context 'when authenticated via a session (no token)' do
        it 'sets a nil access token' do
          expect(GitlabSchema).to receive(:execute).with(
            anything,
            hash_including(
              context: hash_including(access_token: nil)
            )
          ).and_return(graphql_result)

          subscribe(subscribe_params)
        end
      end
    end

    context "with a query listing a runner's jobs by a completed status", :clean_gitlab_redis_rate_limiting,
      feature_category: :fleet_visibility do
      let_it_be(:group) { create(:group, owners: user) }
      let_it_be(:runner) { create(:ci_runner, :group, groups: [group]) }
      let_it_be(:pipeline) { create(:ci_pipeline, project: create(:project, group: group)) }
      let_it_be(:job) { create(:ci_build, :failed, runner: runner, pipeline: pipeline) }

      let(:jobs_query) do
        %(query { runner(id: "#{runner.to_global_id}") { jobs(statuses: [FAILED]) { nodes { id } } } })
      end

      before do
        stub_application_setting(runner_job_list_completed_statuses_limit_per_user: 1)
      end

      it 'rate limits the user past the limit', :aggregate_failures do
        subscribe(query: jobs_query, variables: {})

        expect(transmissions.last.dig('result', 'data', 'runner', 'jobs', 'nodes'))
          .to contain_exactly('id' => job.to_global_id.to_s)

        subscribe(query: jobs_query, variables: {})

        expect(transmissions.last.dig('result', 'errors'))
          .to contain_exactly(a_hash_including('message' => Gitlab::ApplicationRateLimiter.throttled_error_message))
      end
    end

    describe 'query normalization' do
      let(:raw_query) { "query NormTest { __typename(arg: \"hello\nworld\") }" }
      let(:normalized_query) { "query NormTest { __typename(arg: \"hello\\nworld\") }" }

      it 'normalizes single-quoted newlines before passing to GitlabSchema.execute' do
        expect(GitlabSchema).to receive(:execute).with(
          normalized_query,
          hash_including(:context, :variables, :operation_name)
        ).and_call_original

        subscribe(query: raw_query, variables: {})
      end
    end
  end
end
