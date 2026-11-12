# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Mutations::GitlabSubscriptions::BudgetCaps::UpsertUserOverrides, :clean_gitlab_redis_rate_limiting,
  feature_category: :consumables_cost_management do
  include GraphqlHelpers

  let_it_be(:owner) { create(:user) }
  let_it_be(:admin) { create(:admin) }
  let_it_be(:target_user) { create(:user) }
  let_it_be(:group) { create(:group, owners: owner, developers: target_user) }

  let(:client) { instance_double(Gitlab::SubscriptionPortal::SubscriptionUsageClient) }
  let(:overrides) { [{ user_id: target_user.to_global_id, cap: 100.0, enabled: true }] }

  before do
    allow(Gitlab::SubscriptionPortal::SubscriptionUsageClient).to receive(:new).and_return(client)
    allow(client).to receive_messages(
      upsert_user_budget_cap_overrides: { success: true, userBudgetCapOverrides: [] },
      upsert_flat_user_cap: { success: true, subscriptionBudgetCap: { flatUserCap: 100.0, flatUserCapEnabled: true } }
    )
  end

  def resolve_or_error(user = owner, namespace_path: group.full_path)
    described_class
      .new(object: nil, context: query_context(user: user), field: nil)
      .resolve(overrides: overrides, namespace_path: namespace_path)
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
          resolve_or_error
        end

        def resolve_unauthorized
          resolve_or_error(create(:user))
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
          resolve_or_error(admin, namespace_path: nil)
        end

        def resolve_unauthorized
          resolve_or_error(create(:user), namespace_path: nil)
        end
      end
    end

    context 'when the rate limit is exceeded and enforced' do
      before do
        stub_feature_flags(enforce_budget_cap_rate_limits: true)
        allow(Gitlab::ApplicationRateLimiter).to receive(:throttled?).and_return(true)
        allow(Namespace).to receive(:find_by_full_path).with(group.full_path).and_return(group)
      end

      it 'returns the throttled error without loading the eligible users of the namespace' do
        expect(group).not_to receive(:gitlab_duo_eligible_user_ids)

        expect(resolve_or_error).to be_a(Gitlab::Graphql::Errors::ResourceNotAvailable)
          .and have_attributes(message: Gitlab::ApplicationRateLimiter.throttled_error_message)
      end
    end

    context 'when the budget is one call below the minute limit' do
      let(:minute_limit) do
        Gitlab::ApplicationRateLimiter::LabkitAdapter::SupportedRateLimits.limit_for(:budget_cap_update_per_minute)
      end

      before do
        Gitlab::ApplicationRateLimiter.throttled?(:budget_cap_update_per_minute, scope: { user: owner },
          cost: minute_limit - 1)
        stub_feature_flags(enforce_budget_cap_rate_limits: true)
      end

      it 'resolves when only the overrides call counts' do
        expect(resolve_or_error).to be_a(Hash)
      end

      it 'shares one budget with upsertFlatUserCap' do
        flat_cap_result = Mutations::GitlabSubscriptions::BudgetCaps::UpsertFlatUserCap
          .new(object: nil, context: query_context(user: owner), field: nil)
          .resolve(flat_user_cap: 100.0, flat_user_cap_enabled: true, namespace_path: group.full_path)

        expect(flat_cap_result).to be_a(Hash)
        expect(resolve_or_error).to be_a(Gitlab::Graphql::Errors::ResourceNotAvailable)
          .and have_attributes(message: Gitlab::ApplicationRateLimiter.throttled_error_message)
      end
    end
  end
end
