# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Mutations::GitlabSubscriptions::BudgetCaps::UpsertFlatUserCap, :clean_gitlab_redis_rate_limiting,
  feature_category: :consumables_cost_management do
  include GraphqlHelpers

  let_it_be(:owner) { create(:user) }
  let_it_be(:admin) { create(:admin) }
  let_it_be(:group) { create(:group, owners: owner) }

  let(:client) { instance_double(Gitlab::SubscriptionPortal::SubscriptionUsageClient) }

  before do
    allow(Gitlab::SubscriptionPortal::SubscriptionUsageClient).to receive(:new).and_return(client)
    allow(client).to receive(:upsert_flat_user_cap).and_return(
      { success: true, subscriptionBudgetCap: { flatUserCap: 100.0, flatUserCapEnabled: true } }
    )
  end

  def mutation_for(user)
    described_class.new(object: nil, context: query_context(user: user), field: nil)
  end

  def resolve_or_error(user, **args)
    mutation_for(user).resolve(flat_user_cap: 100.0, flat_user_cap_enabled: true, **args)
  rescue Gitlab::Graphql::Errors::ResourceNotAvailable => e
    e
  end

  describe '#resolve' do
    context 'with a namespace' do
      it_behaves_like 'subscription usage rate limited resolver' do
        let(:rate_limit_keys) { %i[budget_cap_update_per_minute budget_cap_update_per_hour budget_cap_update_per_day] }
        let(:enforce_flag) { :enforce_budget_cap_rate_limits }
        let(:rate_limit_log_message) { 'Budget cap rate limit exceeded' }
        let(:rate_limit_user) { owner }
        let(:rate_limit_namespace) { group }
        let(:expected_result_class) { Hash }

        def resolve_rate_limited
          resolve_or_error(owner, namespace_path: group.full_path)
        end

        def resolve_unauthorized
          resolve_or_error(create(:user), namespace_path: group.full_path)
        end
      end
    end

    context 'with the instance subscription', :enable_admin_mode do
      let(:license) { build(:license) }

      before do
        allow(License).to receive_messages(billable_license: license, current: license)
      end

      it_behaves_like 'subscription usage rate limited resolver', namespace_actor: false do
        let(:rate_limit_keys) { %i[budget_cap_update_per_minute budget_cap_update_per_hour budget_cap_update_per_day] }
        let(:enforce_flag) { :enforce_budget_cap_rate_limits }
        let(:rate_limit_log_message) { 'Budget cap rate limit exceeded' }
        let(:rate_limit_user) { admin }
        let(:rate_limit_namespace) { nil }
        let(:expected_result_class) { Hash }

        def resolve_rate_limited
          resolve_or_error(admin)
        end

        def resolve_unauthorized
          resolve_or_error(create(:user))
        end
      end
    end
  end
end
