# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Gitlab::Graphql::Subscriptions::RateLimitPolicy, feature_category: :api do
  let(:project) { build_stubbed(:project) }
  let(:args) { { project_id: project.to_gid } }
  let(:object) { build_stubbed(:ci_pipeline, project: project) }

  subject(:policy) do
    described_class.new(:ci_pipeline_statuses_subscription,
      ->(args, _object) { { project: args[:project_id].model_id } })
  end

  # The rule name is part of every labkit Redis key of the rule. Other features share this Redis instance.
  def rule_counters
    ::Gitlab::Redis::RateLimiting.with do |redis|
      redis.scan_each(match: '*limit_ci_pipeline_status_events_by_project*').to_a
    end
  end

  describe '#throttled?' do
    it 'counts the event against the scope built from the trigger' do
      expect(Gitlab::ApplicationRateLimiter).to receive(:throttled?)
        .with(:ci_pipeline_statuses_subscription, scope: { project: project.id.to_s })
        .and_return(true)

      expect(policy.throttled?(args, object)).to be(true)
    end

    it 'counts the event', :clean_gitlab_redis_rate_limiting do
      policy.throttled?(args, object)

      expect(rule_counters).not_to be_empty
    end
  end

  describe '#exhausted?' do
    it 'reads the budget of the scope built from the trigger' do
      expect(Gitlab::ApplicationRateLimiter).to receive(:peek)
        .with(:ci_pipeline_statuses_subscription, scope: { project: project.id.to_s })
        .and_return(true)

      expect(policy.exhausted?(args, object)).to be(true)
    end

    it 'does not count the event', :clean_gitlab_redis_rate_limiting do
      policy.exhausted?(args, object)

      expect(rule_counters).to be_empty
    end
  end
end
