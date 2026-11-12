# frozen_string_literal: true

# Host defines: entity, user, perform_write and perform_skipped (procs), and
# write_delta (the change perform_write makes to ProtectedBranch.count).
RSpec.shared_examples 'a rate limited protected branch write' do
  let(:rate_limit_rule) do
    Gitlab::ApplicationRateLimiter::LabkitAdapter::SupportedRateLimits.rule_for(:protected_branch_write)
  end

  describe 'the limiter contract' do
    it 'scopes the check by exactly the characteristics the registered rule counts on' do
      expect(Gitlab::ApplicationRateLimiter).to receive(:throttled?) do |key, **opts|
        expect(key).to eq(:protected_branch_write)
        expect(opts[:scope].keys).to match_array(rate_limit_rule.characteristics)
        false
      end

      perform_write.call
    end

    # ApplicationRateLimiter rejects an unknown scope key but not a missing one:
    # labkit substitutes a sentinel and every namespace shares a bucket.
    it 'increments the counter the registered rule reads', :clean_gitlab_redis_rate_limiting do
      perform_write.call

      counter_key = "labkit:rl:{applimiter_protected_branch_write:#{rate_limit_rule.name}" \
        ":user:#{user.id}:namespace:#{entity.root_ancestor.id}}"
      count = Gitlab::Redis::RateLimiting.with { |redis| redis.get(counter_key) }

      expect(count.to_i).to eq(1)
    end

    it 'enforces the threshold from application settings', :clean_gitlab_redis_rate_limiting do
      stub_application_setting(protected_branch_write_limit: 1)
      charge_the_limit

      expect { perform_write.call }.to raise_error(RateLimitedService::RateLimitedError)
    end

    # The key is staged, so the registry routes the check to the :log twin.
    it 'counts but does not reject while enforcement is disabled', :clean_gitlab_redis_rate_limiting do
      stub_feature_flags(protected_branch_write_rate_limit_enforce: false)
      stub_application_setting(protected_branch_write_limit: 1)
      charge_the_limit

      expect { perform_write.call }.to change { ProtectedBranch.count }.by(write_delta)
    end

    def charge_the_limit
      Gitlab::ApplicationRateLimiter.throttled?(
        :protected_branch_write, scope: { user: user, namespace: entity.root_ancestor }
      )
    end
  end

  context 'when the limit is exceeded' do
    before do
      allow(Gitlab::ApplicationRateLimiter).to receive(:throttled?).and_call_original
      allow(Gitlab::ApplicationRateLimiter).to receive(:throttled?)
        .with(:protected_branch_write, scope: { user: user, namespace: entity.root_ancestor })
        .and_return(true)
    end

    it 'rejects the write', :aggregate_failures do
      expect { perform_write.call }.to raise_error(RateLimitedService::RateLimitedError)
        .and not_change { ProtectedBranch.count }
    end

    it 'performs the write when the caller skips the rate limit' do
      expect { perform_skipped.call }.to change { ProtectedBranch.count }.by(write_delta)
    end
  end

  context 'when the limit is set to zero' do
    before do
      stub_application_setting(protected_branch_write_limit: 0)
    end

    it 'performs the write without counting it', :clean_gitlab_redis_rate_limiting, :aggregate_failures do
      expect(Gitlab::ApplicationRateLimiter::LabkitAdapter).not_to receive(:run!)

      expect { perform_write.call }.to change { ProtectedBranch.count }.by(write_delta)
    end
  end
end
