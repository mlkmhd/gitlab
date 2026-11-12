# frozen_string_literal: true

# Requires `execute`, `current_user` and `service_class` (the service that validates the configuration).
RSpec.shared_examples 'an AI Catalog config validation rate limited mutation' do |mutation_name, payload_field|
  describe 'config validation rate limit', :clean_gitlab_redis_rate_limiting, :freeze_time do
    def exhaust_config_validation_rate_limit_for(user)
      30.times do
        Gitlab::ApplicationRateLimiter.throttled?(:ai_catalog_config_validation, scope: { user: user })
      end
    end

    context 'when the user is over the limit' do
      before do
        exhaust_config_validation_rate_limit_for(current_user)
      end

      it 'returns an error and does not call the service' do
        expect(service_class).not_to receive(:new)

        execute

        expect(graphql_data_at(mutation_name, payload_field)).to be_nil
        expect(graphql_data_at(mutation_name, :errors)).to contain_exactly(
          'You have saved agents, flows, or triggers too many times. Try again in a minute.'
        )
      end

      it 'logs the throttled request with the user to the auth log' do
        expect(Gitlab::AuthLogger).to receive(:error).with(
          hash_including(
            message: 'Application_Rate_Limiter_Request',
            env: :ai_catalog_config_validation_request_limit,
            user_id: current_user.id
          )
        )

        execute
      end
    end

    context 'when a user without access is over the limit' do
      let(:current_user) { create(:user) }

      before do
        exhaust_config_validation_rate_limit_for(current_user)
      end

      it_behaves_like 'a mutation that returns a top-level access error'
    end

    context 'when another user is over the limit' do
      before do
        exhaust_config_validation_rate_limit_for(create(:user))
      end

      it 'calls the service' do
        expect(service_class).to receive(:new).and_call_original

        execute
      end
    end
  end
end
