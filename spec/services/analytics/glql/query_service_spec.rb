# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Analytics::Glql::QueryService, feature_category: :glql do
  let_it_be(:user) { create(:user) }
  let(:query) { 'query { __typename }' }
  let(:original_query) { 'type = issue' }
  let(:variables) { { 'limit' => 10 } }
  let(:context) { { is_sessionless_user: true } }
  let(:request) { instance_double(ActionDispatch::Request, headers: {}) }
  let(:rate_limit_message) do
    'Query temporarily blocked due to repeated timeouts. Please try again later or narrow your search scope.'
  end

  let(:service) do
    described_class.new(
      current_user: user,
      original_query: original_query,
      request: request,
      current_organization: nil
    )
  end

  before do
    Gitlab::Redis::RateLimiting.with(&:flushdb)
    allow(RequestStore).to receive(:store).and_return({})
  end

  describe '#execute' do
    context 'when GraphQL execution succeeds' do
      let(:graphql_result) do
        {
          'data' => { '__typename' => 'Query' },
          'errors' => nil
        }
      end

      before do
        allow(GitlabSchema).to receive(:execute).and_return(graphql_result)
        allow(RequestStore).to receive(:store).and_return({ graphql_logs: [{ complexity: 5 }] })
      end

      it 'returns successful result with metrics' do
        result = service.execute(query: query, variables: variables, context: context)

        expect(result).to include(
          data: { '__typename' => 'Query' },
          errors: nil,
          complexity_score: 5,
          timeout_occurred: false,
          rate_limited: false
        )
        expect(result[:duration_s]).to be_a(Float)
      end

      it 'calls LoggingService to log execution metrics' do
        logging_service = instance_double(Analytics::Glql::LoggingService)
        expect(Analytics::Glql::LoggingService).to receive(:new).with(
          current_user: user,
          result: hash_including(
            data: { '__typename' => 'Query' },
            complexity_score: 5,
            timeout_occurred: false
          ),
          query_sha: service.send(:query_sha)
        ).and_return(logging_service)
        expect(logging_service).to receive(:execute)

        service.execute(query: query, variables: variables, context: context)
      end

      it 'calls GitlabSchema.execute with correct parameters' do
        expected_context = {
          current_user: user,
          current_organization: nil,
          request: request,
          is_sessionless_user: true
        }

        expect(GitlabSchema).to receive(:execute).with(
          query,
          variables: variables,
          context: expected_context,
          operation_name: nil
        )

        service.execute(query: query, variables: variables, context: context)
      end

      it 'passes operation_name to GitlabSchema.execute when provided' do
        expected_context = {
          current_user: user,
          current_organization: nil,
          request: request,
          is_sessionless_user: true
        }

        expect(GitlabSchema).to receive(:execute).with(
          query,
          variables: variables,
          context: expected_context,
          operation_name: 'TestOp'
        )

        service.execute(query: query, variables: variables, context: context, operation_name: 'TestOp')
      end

      it 'tracks SLI metrics for successful execution' do
        expect(Gitlab::Metrics::GlqlSlis).to receive(:record_error).with(
          labels: hash_including(error_type: nil),
          error: false
        )

        expect(Gitlab::Metrics::GlqlSlis).to receive(:record_apdex).with(
          labels: hash_including(error_type: nil),
          success: true
        )

        service.execute(query: query, variables: variables, context: context)
      end

      it 'records the SLIs with the labels they are initialized with' do
        expected_labels = {
          endpoint_id: 'POST /api/:version/glql',
          feature_category: 'glql',
          query_urgency: :low,
          error_type: nil,
          client: 'other'
        }

        expect(Gitlab::Metrics::GlqlSlis).to receive(:record_error).with(labels: expected_labels, error: false)
        expect(Gitlab::Metrics::GlqlSlis).to receive(:record_apdex).with(labels: expected_labels, success: true)

        Gitlab::ApplicationContext.with_context(caller_id: 'POST /api/:version/glql') do
          service.execute(query: query, variables: variables, context: context)
        end
      end

      it 'labels queries from Duo Agent Platform tools' do
        expect(Gitlab::Metrics::GlqlSlis).to receive(:record_error)
          .with(labels: hash_including(client: 'duo_agent'), error: false)

        Gitlab::ApplicationContext.with_context(duo_workflow_id: '123') do
          service.execute(query: query, variables: variables, context: context)
        end
      end
    end

    context 'when GraphQL execution has errors' do
      let(:graphql_result) do
        {
          'data' => nil,
          'errors' => [{ 'message' => 'Field not found' }]
        }
      end

      before do
        allow(GitlabSchema).to receive(:execute).and_return(graphql_result)
      end

      it 'returns result with errors normalized to symbol keys' do
        result = service.execute(query: query, variables: variables, context: context)

        expect(result).to include(
          data: nil,
          errors: [{ message: 'Field not found' }],
          timeout_occurred: false,
          rate_limited: false
        )
      end
    end

    context 'when GraphQL execution returns nil' do
      before do
        allow(GitlabSchema).to receive(:execute).and_return(nil)
      end

      it 'handles nil result gracefully' do
        result = service.execute(query: query, variables: variables, context: context)

        expect(result).to include(
          data: nil,
          errors: nil,
          timeout_occurred: false,
          rate_limited: false
        )
      end
    end

    context 'when GraphQL errors carry extensions' do
      let(:graphql_result) do
        {
          'data' => nil,
          'errors' => [{ 'message' => 'not available', 'extensions' => { 'code' => 'SIPHON_REPLICATION_DISABLED' } }]
        }
      end

      before do
        allow(GitlabSchema).to receive(:execute).and_return(graphql_result)
      end

      it 'preserves the extensions so clients can map error codes' do
        result = service.execute(query: query, variables: variables, context: context)

        expect(result[:errors]).to eq([{
          message: 'not available',
          extensions: { 'code' => 'SIPHON_REPLICATION_DISABLED' }
        }])
      end
    end

    context 'when GraphQL errors contain non-hash elements' do
      let(:graphql_result) do
        {
          'data' => nil,
          'errors' => ['Simple string error', { 'message' => 'Hash error' }]
        }
      end

      before do
        allow(GitlabSchema).to receive(:execute).and_return(graphql_result)
      end

      it 'preserves non-hash errors and normalizes hash errors' do
        result = service.execute(query: query, variables: variables, context: context)

        expect(result).to include(
          data: nil,
          errors: ['Simple string error', { message: 'Hash error' }],
          timeout_occurred: false,
          rate_limited: false
        )
      end
    end

    context 'when GraphQL execution returns partial data with errors' do
      let(:graphql_result) do
        {
          'data' => { 'user' => { 'id' => '1' } },
          'errors' => [{ 'message' => 'Field error' }]
        }
      end

      before do
        allow(GitlabSchema).to receive(:execute).and_return(graphql_result)
        allow(RequestStore).to receive(:store).and_return({ graphql_logs: [{ complexity: 8 }] })
      end

      it 'returns both data and errors normalized to symbol keys' do
        result = service.execute(query: query, variables: variables, context: context)

        expect(result).to include(
          data: { 'user' => { 'id' => '1' } },
          errors: [{ message: 'Field error' }],
          complexity_score: 8,
          timeout_occurred: false,
          rate_limited: false
        )
      end
    end

    context 'when ActiveRecord::QueryAborted is raised' do
      before do
        allow(GitlabSchema).to receive(:execute).and_raise(ActiveRecord::QueryAborted)
        allow(RequestStore).to receive(:store).and_return({ graphql_logs: [{ complexity: 3 }] })
      end

      it 'returns timeout result and increments rate limiter' do
        allow(Gitlab::ApplicationRateLimiter).to receive(:peek).and_call_original
        allow(Gitlab::ApplicationRateLimiter).to receive(:throttled?).and_call_original
        expect(Gitlab::ApplicationRateLimiter).to receive(:peek).with(:glql, anything).and_return(false)
        expect(Gitlab::ApplicationRateLimiter).to receive(:throttled?).with(
          :glql,
          hash_including(scope: { query_sha: service.send(:query_sha) })
        )

        result = service.execute(query: query, variables: variables, context: context)

        expect(result).to include(
          data: nil,
          errors: [{ message: 'Query timed out' }],
          timeout_occurred: true,
          rate_limited: false
        )
      end

      it 'calls LoggingService to log timeout' do
        allow(Gitlab::ApplicationRateLimiter).to receive(:peek).and_return(false)
        allow(Gitlab::ApplicationRateLimiter).to receive(:throttled?)

        logging_service = instance_double(Analytics::Glql::LoggingService)
        expect(Analytics::Glql::LoggingService).to receive(:new).with(
          current_user: user,
          result: hash_including(
            timeout_occurred: true,
            complexity_score: 3
          ),
          query_sha: service.send(:query_sha)
        ).and_return(logging_service)
        expect(logging_service).to receive(:execute)

        service.execute(query: query, variables: variables, context: context)
      end

      it 'tracks SLI metrics for timeout' do
        allow(Gitlab::ApplicationRateLimiter).to receive(:peek).and_return(false)
        allow(Gitlab::ApplicationRateLimiter).to receive(:throttled?)

        expect(Gitlab::Metrics::GlqlSlis).to receive(:record_error).with(
          labels: hash_including(error_type: :query_aborted),
          error: true
        )

        service.execute(query: query, variables: variables, context: context)
      end
    end

    context 'when rate limiting is triggered' do
      before do
        allow(Gitlab::ApplicationRateLimiter).to receive(:peek).and_return(true)
        allow(RequestStore).to receive(:store).and_return({ graphql_logs: [] })
      end

      it 'returns rate limited result' do
        result = service.execute(query: query, variables: variables, context: context)

        expect(result).to include(
          data: nil,
          errors: [{ message: rate_limit_message }],
          timeout_occurred: false,
          rate_limited: true
        )
      end

      it 'does not execute GraphQL query' do
        expect(GitlabSchema).not_to receive(:execute)

        service.execute(query: query, variables: variables, context: context)
      end

      it 'does not record the GLQL SLIs' do
        expect(Gitlab::Metrics::GlqlSlis).not_to receive(:record_error)
        expect(Gitlab::Metrics::GlqlSlis).not_to receive(:record_apdex)

        service.execute(query: query, variables: variables, context: context)
      end
    end

    context 'when a DB-time budget is spent' do
      before do
        stub_application_setting(glql_db_seconds_per_user_limit: 1)
        Gitlab::ApplicationRateLimiter.throttled?(:glql_db_seconds_by_user, scope: { user: user }, cost: 2.0)
        allow(Gitlab::AppJsonLogger).to receive(:info)
      end

      it 'returns a rate limited result with the time to wait, without running the query', :aggregate_failures do
        expect(GitlabSchema).not_to receive(:execute)

        result = service.execute(query: query, variables: variables, context: context)

        expect(result).to include(
          data: nil,
          errors: [{ message: Gitlab::ApplicationRateLimiter.throttled_error_message }],
          rate_limited: true,
          retry_after: 15.minutes.to_i
        )
        expect(Gitlab::AppJsonLogger).to have_received(:info).with(a_hash_including(
          'message' => 'GLQL DB-time budget exceeded',
          'glql_budget_keys' => ['glql_db_seconds_by_user'],
          'glql_budget_enforced' => true
        ))
      end

      context 'when enforcement is disabled' do
        before do
          stub_feature_flags(enforce_glql_db_time_budgets: false)
          allow(GitlabSchema).to receive(:execute).and_return({ 'data' => { '__typename' => 'Query' } })
        end

        it 'runs the query and only logs the spent budget', :aggregate_failures do
          result = service.execute(query: query, variables: variables, context: context)

          expect(result).to include(data: { '__typename' => 'Query' }, rate_limited: false)
          expect(Gitlab::AppJsonLogger).to have_received(:info).with(a_hash_including(
            'glql_budget_keys' => ['glql_db_seconds_by_user'],
            'glql_budget_enforced' => false
          ))
        end
      end
    end

    context 'when charging DB time' do
      it 'charges the budget after a successful query' do
        allow(GitlabSchema).to receive(:execute).and_return({ 'data' => { '__typename' => 'Query' } })
        expect_next_instance_of(Analytics::Glql::DbTimeBudget) do |budget|
          expect(budget).to receive(:charge!)
        end

        service.execute(query: query, variables: variables, context: context)
      end

      it 'charges the budget after a query that timed out' do
        allow(GitlabSchema).to receive(:execute).and_raise(ActiveRecord::QueryAborted)
        expect_next_instance_of(Analytics::Glql::DbTimeBudget) do |budget|
          expect(budget).to receive(:charge!)
        end

        service.execute(query: query, variables: variables, context: context)
      end
    end

    context 'when other StandardError is raised' do
      let(:error) { StandardError.new('Something went wrong') }

      before do
        allow(GitlabSchema).to receive(:execute).and_raise(error)
      end

      it 'returns error result with exception' do
        result = service.execute(query: query, variables: variables, context: context)

        expect(result).to include(
          data: nil,
          errors: [{ message: 'Something went wrong' }],
          timeout_occurred: false,
          rate_limited: false,
          exception: error
        )
      end

      it 'tracks SLI metrics for other errors' do
        expect(Gitlab::Metrics::GlqlSlis).to receive(:record_error).with(
          labels: hash_including(error_type: :other),
          error: true
        )

        service.execute(query: query, variables: variables, context: context)
      end
    end

    context 'with load balancing enabled', :db_load_balancing do
      before do
        allow(GitlabSchema).to receive(:execute).and_return({ 'data' => { '__typename' => 'Query' }, 'errors' => nil })
      end

      it 'uses load balancing session map' do
        expect(Gitlab::Database::LoadBalancing::SessionMap).to receive(:use_replica_if_available).and_yield

        result = service.execute(query: query, variables: variables, context: context)

        expect(result).to include(
          data: { '__typename' => 'Query' },
          errors: nil,
          timeout_occurred: false,
          rate_limited: false
        )
      end
    end

    context 'when graphql_logs are empty' do
      before do
        allow(GitlabSchema).to receive(:execute).and_return(
          { 'data' => { '__typename' => 'Query' }, 'errors' => nil }
        )
        allow(RequestStore).to receive(:store).and_return({ graphql_logs: [] })
      end

      it 'returns result with nil complexity_score' do
        result = service.execute(query: query, variables: variables, context: context)

        expect(result).to include(
          data: { '__typename' => 'Query' },
          complexity_score: nil,
          timeout_occurred: false,
          rate_limited: false
        )
      end
    end

    context 'when graphql_logs have no complexity field' do
      before do
        allow(GitlabSchema).to receive(:execute).and_return(
          { 'data' => { '__typename' => 'Query' }, 'errors' => nil }
        )
        allow(RequestStore).to receive(:store).and_return({
          graphql_logs: [{ other_field: 'value' }]
        })
      end

      it 'returns result with nil complexity_score' do
        result = service.execute(query: query, variables: variables, context: context)

        expect(result).to include(
          data: { '__typename' => 'Query' },
          complexity_score: nil,
          timeout_occurred: false,
          rate_limited: false
        )
      end
    end

    context 'when no graphql_logs in RequestStore during execution' do
      before do
        allow(GitlabSchema).to receive(:execute).and_return(
          { 'data' => { '__typename' => 'Query' }, 'errors' => nil }
        )
        allow(RequestStore).to receive(:store).and_return({ graphql_logs: nil })
      end

      it 'does not raise error' do
        expect do
          service.execute(query: query, variables: variables, context: context)
        end.not_to raise_error
      end
    end

    context 'when request has referer header' do
      let(:request_with_referer) do
        instance_double(ActionDispatch::Request, headers: { 'Referer' => 'https://example.com/dashboard' })
      end

      let(:service_with_referer) do
        described_class.new(
          current_user: user,
          original_query: original_query,
          request: request_with_referer,
          current_organization: nil
        )
      end

      before do
        allow(GitlabSchema).to receive(:execute).and_return(
          { 'data' => { '__typename' => 'Query' }, 'errors' => nil }
        )
        allow(RequestStore).to receive(:store).and_return({
          graphql_logs: [{ complexity: 5 }]
        })
      end

      it 'executes successfully with referer header' do
        result = service_with_referer.execute(query: query, variables: variables, context: context)

        expect(result).to include(
          data: { '__typename' => 'Query' },
          complexity_score: 5,
          timeout_occurred: false,
          rate_limited: false
        )
      end
    end
  end

  describe 'exception handling' do
    it 'defines GlqlQueryLockedError' do
      expect(described_class::GlqlQueryLockedError).to be < StandardError
    end

    it 'can raise and rescue GlqlQueryLockedError' do
      expect do
        raise described_class::GlqlQueryLockedError, 'Test message'
      end.to raise_error(described_class::GlqlQueryLockedError, 'Test message')
    end
  end
end
