# frozen_string_literal: true

require 'spec_helper'

RSpec.describe GitlabSubscriptions::CreateHandRaiseLeadService, feature_category: :acquisition do
  describe '#execute' do
    let_it_be(:user) { create(:user) }

    let(:params) { { first_name: 'Jeremy', product_interaction: 'Hand Raise PQL', existing_plan: 'free' } }

    subject(:execute) { described_class.new(user: user).execute(params) }

    context 'when hand raise lead call is made successfully' do
      let(:response) { { success: true } }

      it 'returns success: true' do
        expect(Gitlab::SubscriptionPortal::Client).to receive(:generate_lead).with(params).and_return(response)

        result = execute

        expect(result.is_a?(ServiceResponse)).to be true
        expect(result.success?).to be true
      end
    end

    context 'with an error while creating hand raise lead call is made successful' do
      let(:response) { { success: false, data: { errors: ['some error'] } } }

      it 'returns success: false with errors' do
        expect(Gitlab::SubscriptionPortal::Client).to receive(:generate_lead).with(params).and_return(response)

        result = execute

        expect(result.is_a?(ServiceResponse)).to be true
        expect(result.success?).to be false
        expect(result.message).to match_array(['some error'])
      end
    end

    context 'with the hand_raise_lead_create rate limit' do
      it 'counts the lead against the user' do
        allow(Gitlab::SubscriptionPortal::Client).to receive(:generate_lead).and_return({ success: true })

        expect(Gitlab::ApplicationRateLimiter).to receive(:throttled?)
          .with(:hand_raise_lead_create, scope: { user: user }).and_call_original

        execute
      end

      context 'when over the limit' do
        before do
          allow(Gitlab::ApplicationRateLimiter).to receive(:throttled?)
            .with(:hand_raise_lead_create, scope: { user: user }).and_return(true)
        end

        it 'logs the request and does not send the lead', :aggregate_failures do
          expect(Gitlab::AuthLogger).to receive(:error).with(
            message: 'Application_Rate_Limiter_Request',
            env: :hand_raise_lead_create_request_limit,
            user_id: user.id,
            username: user.username
          )
          expect(Gitlab::SubscriptionPortal::Client).not_to receive(:generate_lead)

          result = execute

          expect(result).to be_error
          expect(result.reason).to eq(:rate_limited)
          expect(result.message).to eq(Gitlab::ApplicationRateLimiter.throttled_error_message)
        end

        context 'when enforce_hand_raise_lead_rate_limit is disabled' do
          before do
            stub_feature_flags(enforce_hand_raise_lead_rate_limit: false)
          end

          it 'logs the request and still sends the lead', :aggregate_failures do
            expect(Gitlab::AuthLogger).to receive(:error).with(
              hash_including(message: 'Application_Rate_Limiter_Request', env: :hand_raise_lead_create_request_limit)
            )
            expect(Gitlab::SubscriptionPortal::Client).to receive(:generate_lead).with(params)
              .and_return({ success: true })

            expect(execute).to be_success
          end
        end
      end
    end
  end
end
