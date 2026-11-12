# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Analytics::Glql::DbTimeBudget, :clean_gitlab_redis_rate_limiting, :request_store,
  feature_category: :custom_dashboards_foundation do
  let_it_be(:user) { create(:user) }
  let_it_be(:other_user) { create(:user) }

  let(:query_sha) { Digest::SHA256.hexdigest('type = issue') }
  let(:other_query_sha) { Digest::SHA256.hexdigest('type = epic') }
  let(:request) { instance_double(ActionDispatch::Request, ip: '192.0.2.1') }

  def budget_for(current_user, sha: query_sha, req: request)
    described_class.new(current_user: current_user, query_sha: sha, request: req)
  end

  def spend(seconds, budget)
    Gitlab::SafeRequestStore[:db_main_duration_s] = seconds
    budget.charge!
  end

  context 'when the limits are 0' do
    it 'never reports a spent budget' do
      spend(1000.0, budget_for(user))

      expect(budget_for(user).exceeded_keys).to be_empty
    end
  end

  context 'with limits set' do
    before do
      stub_application_setting(
        glql_db_seconds_per_query_limit: 10,
        glql_db_seconds_per_user_limit: 5,
        glql_db_seconds_per_ip_limit: 3
      )
    end

    it 'reports nothing while the budgets have time left' do
      spend(2.5, budget_for(user))

      expect(budget_for(user).exceeded_keys).to be_empty
    end

    it 'reports the user key once the user has spent their budget' do
      spend(6.0, budget_for(user))

      expect(budget_for(user).exceeded_keys).to contain_exactly(:glql_db_seconds_by_user)
    end

    it 'charges the time on every database, primaries and replicas' do
      allow(Gitlab::Metrics::Subscribers::ActiveRecord).to receive(:load_balancing_metric_query_duration_keys)
        .and_return(%i[db_main_duration_s db_ci_replica_duration_s db_sec_replica_duration_s])
      Gitlab::SafeRequestStore[:db_main_duration_s] = 2.0
      Gitlab::SafeRequestStore[:db_ci_replica_duration_s] = 2.0
      Gitlab::SafeRequestStore[:db_sec_replica_duration_s] = 2.0
      budget_for(user).charge!

      expect(budget_for(user).exceeded_keys).to contain_exactly(:glql_db_seconds_by_user)
    end

    it 'keys the user budget on the user, not the IP address' do
      spend(6.0, budget_for(user))

      expect(budget_for(other_user, sha: other_query_sha).exceeded_keys).to be_empty
    end

    it 'shares the query budget across users', :aggregate_failures do
      spend(4.0, budget_for(user))
      spend(7.0, budget_for(other_user))

      expect(budget_for(user).exceeded_keys).to contain_exactly(:glql_db_seconds_by_query_sha)
      expect(budget_for(user, sha: other_query_sha).exceeded_keys).to be_empty
    end

    context 'without a user' do
      it 'keys the budget on the IP address', :aggregate_failures do
        spend(4.0, budget_for(nil))

        other_ip = instance_double(ActionDispatch::Request, ip: '192.0.2.2')

        expect(budget_for(nil).exceeded_keys).to contain_exactly(:glql_db_seconds_by_ip)
        expect(budget_for(nil, req: other_ip).exceeded_keys).to be_empty
        expect(budget_for(user).exceeded_keys).to be_empty
      end

      it 'only charges the query budget when there is no request' do
        spend(11.0, budget_for(nil, req: nil))

        expect(budget_for(nil, req: nil).exceeded_keys).to contain_exactly(:glql_db_seconds_by_query_sha)
      end
    end

    context 'with a Duo Agent Platform flow token' do
      let(:token_scopes) { %i[ai_workflows mcp] }

      before do
        stub_application_setting(glql_duo_db_seconds_per_user_limit: 8)
        allow(::Current).to receive(:token_info).and_return({ token_scopes: token_scopes })
      end

      it 'charges the Duo budget instead of the user budget', :aggregate_failures do
        spend(6.0, budget_for(user))

        expect(budget_for(user).exceeded_keys).to be_empty
        expect(Gitlab::ApplicationRateLimiter.peek(:glql_db_seconds_by_user, scope: { user: user })).to be(false)

        spend(3.0, budget_for(user, sha: other_query_sha))

        expect(budget_for(user, sha: other_query_sha).exceeded_keys)
          .to contain_exactly(:glql_duo_db_seconds_by_user)
      end

      it 'keys the Duo budget on the user' do
        spend(9.0, budget_for(user))

        expect(budget_for(other_user, sha: other_query_sha).exceeded_keys).to be_empty
      end

      it 'does not use the user budget the user spent without Duo' do
        allow(::Current).to receive(:token_info).and_return({ token_scopes: [:api] })
        spend(6.0, budget_for(user))

        allow(::Current).to receive(:token_info).and_return({ token_scopes: token_scopes })

        expect(budget_for(user, sha: other_query_sha).exceeded_keys).to be_empty
      end
    end

    context 'with a token without the ai_workflows scope' do
      before do
        allow(::Current).to receive(:token_info).and_return({ token_scopes: %i[api mcp] })
      end

      it 'charges the user budget' do
        spend(6.0, budget_for(user))

        expect(budget_for(user).exceeded_keys).to contain_exactly(:glql_db_seconds_by_user)
      end
    end
  end

  describe '#charge!' do
    it 'does not charge anything when the request used no database time' do
      expect(Gitlab::ApplicationRateLimiter).not_to receive(:throttled?)

      budget_for(user).charge!
    end
  end
end
