# frozen_string_literal: true

RSpec.shared_examples 'subscription usage rate limited resolver' do |namespace_actor: true|
  let(:rate_limit_keys) { GitlabSubscriptions::UsageRateLimitable::RATE_LIMIT_KEYS }
  let(:exceeded_rate_limit_key) { rate_limit_keys[1] }
  let(:enforce_flag) { :enforce_subscription_usage_rate_limits }
  let(:rate_limit_scope) { { user: rate_limit_user } }
  let(:rate_limit_log_message) { 'Subscription usage rate limit exceeded' }

  before do
    allow(Gitlab::AppJsonLogger).to receive(:info).and_call_original
  end

  context 'with the real rate limiter', :clean_gitlab_redis_rate_limiting do
    before do
      allow(Gitlab::ApplicationRateLimiter).to receive(:throttled?).and_call_original
    end

    def exhaust_rate_limit(key)
      limit = Gitlab::ApplicationRateLimiter::LabkitAdapter::SupportedRateLimits.limit_for(key)

      Gitlab::ApplicationRateLimiter.throttled?(key, scope: rate_limit_scope, cost: limit)
    end

    it 'counts the call in every window' do
      resolve_rate_limited

      rate_limit_keys.each do |key|
        expect(Gitlab::ApplicationRateLimiter).to have_received(:throttled?).with(key, scope: rate_limit_scope)
      end
    end

    it 'resolves without logging when no window is exceeded' do
      expect(resolve_rate_limited).to be_a(expected_result_class)
      expect(Gitlab::AppJsonLogger).not_to have_received(:info)
        .with(hash_including(Labkit::Fields::LOG_MESSAGE => rate_limit_log_message))
    end

    it 'does not count calls that fail authorization' do
      expect_graphql_error_to_be_created(Gitlab::Graphql::Errors::ResourceNotAvailable) { resolve_unauthorized }
      expect(Gitlab::ApplicationRateLimiter).not_to have_received(:throttled?)
    end

    context 'when an exhausted window has its limit set to 0' do
      before do
        exhaust_rate_limit(rate_limit_keys.first)
        stub_application_setting("#{rate_limit_keys.first}_limit": 0)
        stub_feature_flags(enforce_flag => true)
      end

      it 'resolves without logging' do
        expect(resolve_rate_limited).to be_a(expected_result_class)
        expect(Gitlab::AppJsonLogger).not_to have_received(:info)
          .with(hash_including(Labkit::Fields::LOG_MESSAGE => rate_limit_log_message))
      end
    end

    context 'when every window is exhausted for another user' do
      let_it_be(:other_rate_limit_user) { create(:user) }

      before do
        rate_limit_keys.each do |key|
          limit = Gitlab::ApplicationRateLimiter::LabkitAdapter::SupportedRateLimits.limit_for(key)

          Gitlab::ApplicationRateLimiter.throttled?(key, scope: { user: other_rate_limit_user }, cost: limit + 1)
        end

        stub_feature_flags(enforce_flag => true)
      end

      it 'resolves without logging' do
        expect(resolve_rate_limited).to be_a(expected_result_class)
        expect(Gitlab::AppJsonLogger).not_to have_received(:info)
          .with(hash_including(Labkit::Fields::LOG_MESSAGE => rate_limit_log_message))
      end
    end

    context 'when several windows are exhausted' do
      before do
        exhaust_rate_limit(rate_limit_keys.first)
        exhaust_rate_limit(rate_limit_keys.last)
        stub_feature_flags(enforce_flag => true)
      end

      it 'logs every exceeded window and returns the throttled error' do
        expect_graphql_error_to_be_created(
          Gitlab::Graphql::Errors::ResourceNotAvailable,
          Gitlab::ApplicationRateLimiter.throttled_error_message
        ) { resolve_rate_limited }

        expect(Gitlab::AppJsonLogger).to have_received(:info).with(
          hash_including(
            Labkit::Fields::LOG_MESSAGE => rate_limit_log_message,
            Labkit::Fields::ADDITIONAL_DETAILS =>
              "exceeded_rate_limits: '#{rate_limit_keys.first},#{rate_limit_keys.last}', throttled: true"
          )
        )
      end
    end
  end

  context 'when a window is exceeded' do
    before do
      rate_limit_keys.each do |key|
        allow(Gitlab::ApplicationRateLimiter).to receive(:throttled?)
          .with(key, scope: rate_limit_scope)
          .and_return(key == exceeded_rate_limit_key)
      end
    end

    context 'when the enforce flag is disabled' do
      before do
        stub_feature_flags(enforce_flag => false)
      end

      it 'logs the exceeded window and resolves' do
        expect(resolve_rate_limited).to be_a(expected_result_class)
        expect(Gitlab::SubscriptionPortal::SubscriptionUsageClient).to have_received(:new)
        expect(Gitlab::AppJsonLogger).to have_received(:info).with(
          hash_including(
            Labkit::Fields::LOG_MESSAGE => rate_limit_log_message,
            Labkit::Fields::ADDITIONAL_DETAILS =>
              "exceeded_rate_limits: '#{exceeded_rate_limit_key}', throttled: false",
            Labkit::Fields::CLASS_NAME => described_class.name,
            Labkit::Fields::GL_USER_ID => rate_limit_user.id,
            Labkit::Fields::GL_ROOT_NAMESPACE_ID => rate_limit_namespace&.id
          )
        )
      end
    end

    context 'when the enforce flag is enabled' do
      before do
        stub_feature_flags(enforce_flag => rate_limit_namespace || true)
      end

      it 'logs and returns the throttled error' do
        expect_graphql_error_to_be_created(
          Gitlab::Graphql::Errors::ResourceNotAvailable,
          Gitlab::ApplicationRateLimiter.throttled_error_message
        ) { resolve_rate_limited }

        expect(Gitlab::AppJsonLogger).to have_received(:info)
          .with(hash_including(
            Labkit::Fields::LOG_MESSAGE => rate_limit_log_message,
            Labkit::Fields::ADDITIONAL_DETAILS => a_string_ending_with('throttled: true')
          ))
      end

      it 'does not build the CustomersDot client' do
        expect(Gitlab::SubscriptionPortal::SubscriptionUsageClient).not_to receive(:new)

        resolve_rate_limited
      end
    end

    if namespace_actor
      context 'when the enforce flag is enabled for another namespace' do
        let_it_be(:other_rate_limit_namespace) { create(:group) }

        before do
          stub_feature_flags(enforce_flag => other_rate_limit_namespace)
        end

        it 'logs and resolves' do
          expect(resolve_rate_limited).to be_a(expected_result_class)
          expect(Gitlab::AppJsonLogger).to have_received(:info)
            .with(hash_including(
              Labkit::Fields::LOG_MESSAGE => rate_limit_log_message,
              Labkit::Fields::ADDITIONAL_DETAILS => a_string_ending_with('throttled: false')
            ))
        end
      end
    end
  end
end
