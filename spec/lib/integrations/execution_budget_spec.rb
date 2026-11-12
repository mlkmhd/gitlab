# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Integrations::ExecutionBudget, :clean_gitlab_redis_rate_limiting, :request_store, feature_category: :integrations do
  let_it_be(:plan) { create(:default_plan) }
  let_it_be_with_reload(:plan_limits) { create(:plan_limits, plan: plan) }
  let_it_be(:root_group) { create(:group) }
  let_it_be(:subgroup) { create(:group, parent: root_group) }
  let_it_be(:project) { create(:project, group: subgroup) }

  let(:integration) { create(:jenkins_integration, project: project) }

  def set_limits(**limits)
    plan_limits.update!(limits)
  end

  subject(:budget) { described_class.new(integration) }

  describe '#throttled?' do
    it 'is never throttled when the limit is 0' do
      set_limits(integration_executions: 0)

      expect(Gitlab::ApplicationRateLimiter).not_to receive(:throttled?)
      expect(budget.throttled?).to be(false)
    end

    it 'lets N calls through and throttles call N + 1' do
      set_limits(integration_executions: 2)

      results = Array.new(3) { described_class.new(integration).throttled? }

      expect(results).to eq([false, false, true])
    end

    it 'scopes the counter to the root namespace, not the subgroup' do
      set_limits(integration_executions: 1)

      expect(Gitlab::ApplicationRateLimiter).to receive(:throttled?)
        .with(:integration_executions, scope: { namespace: root_group }, threshold: 1)

      budget.throttled?
    end

    it 'resolves the root namespace for group integrations' do
      set_limits(integration_executions: 1)
      group_integration = create(:jenkins_integration, :group, group: subgroup)

      expect(Gitlab::ApplicationRateLimiter).to receive(:throttled?)
        .with(:integration_executions, scope: { namespace: root_group }, threshold: 1)

      described_class.new(group_integration).throttled?
    end

    it 'uses a separate bucket and limit for Datadog' do
      set_limits(integration_executions: 0, integration_executions_datadog: 1)
      datadog = create(:datadog_integration, project: project)

      expect(Gitlab::ApplicationRateLimiter).to receive(:throttled?)
        .with(:integration_executions_datadog, scope: { namespace: root_group }, threshold: 1)

      described_class.new(datadog).throttled?
    end

    it 'is exempt when the budget key is nil' do
      set_limits(integration_executions: 1)
      allow(integration).to receive(:execution_budget_key).and_return(nil)

      expect(Gitlab::ApplicationRateLimiter).not_to receive(:throttled?)
      expect(budget.throttled?).to be(false)
    end

    it 'is unlimited for integrations without a project or group' do
      set_limits(integration_executions: 1)
      instance_integration = build(:jenkins_integration, :instance)

      expect(Gitlab::ApplicationRateLimiter).not_to receive(:throttled?)
      expect(described_class.new(instance_integration).throttled?).to be(false)
    end

    it 'memoizes the namespace and limit lookups in the request store' do
      set_limits(integration_executions: 100)
      described_class.new(integration).throttled?

      queries = ActiveRecord::QueryRecorder.new do
        3.times { described_class.new(integration).throttled? }
      end

      expect(queries.count).to eq(0)
    end

    it 'resolves the namespace and limit once per instance, even without a request store' do
      set_limits(integration_executions: 100)
      budget

      allow(Gitlab::SafeRequestStore).to receive(:fetch).and_call_original
      expect(Gitlab::SafeRequestStore).to receive(:fetch)
        .with(a_string_starting_with('integration_execution_budget:'))
        .once
        .and_call_original

      budget.throttled?
      budget.root_namespace
      budget.limit
    end
  end
end
