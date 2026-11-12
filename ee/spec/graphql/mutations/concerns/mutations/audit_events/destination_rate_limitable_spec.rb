# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Mutations::AuditEvents::DestinationRateLimitable, :clean_gitlab_redis_rate_limiting, :freeze_time,
  feature_category: :audit_events do
  let_it_be(:user) { create(:user) }
  let_it_be(:group) { create(:group) }

  # Registered at 10 requests per minute per user.
  let(:limit) { 10 }
  let(:request) { ActionDispatch::Request.new(Rack::MockRequest.env_for('/api/graphql', method: 'POST')) }
  let(:context) { { current_user: user, request: request } }

  let(:rate_limited_class) do
    mod = described_class

    Class.new do
      include mod

      attr_reader :context

      def initialize(context)
        @context = context
      end

      def current_user
        context[:current_user]
      end

      def check(group)
        destination_rate_limited?(group)
      end
    end
  end

  def limited?
    rate_limited_class.new(context).check(group)
  end

  describe '#destination_rate_limited?' do
    context 'when the context has a request' do
      it 'is false until the limit is reached, then logs the throttled request to the auth log' do
        expect(Gitlab::AuthLogger).to receive(:error).once.with(
          hash_including(
            message: 'Application_Rate_Limiter_Request',
            env: :audit_event_streaming_destination_mutation_request_limit,
            user_id: user.id,
            username: user.username,
            path: '/api/graphql'
          )
        )

        limit.times { expect(limited?).to be(false) }
        expect(limited?).to be(true)
      end
    end

    context 'when the context has no request' do
      let(:context) { { current_user: user } }

      it 'applies the limit and logs the throttled call to the auth log' do
        expect(Gitlab::AuthLogger).to receive(:error).once.with(
          message: 'Application_Rate_Limiter_Request',
          env: :audit_event_streaming_destination_mutation_request_limit,
          Labkit::Fields::GL_USER_ID => user.id,
          Labkit::Fields::GL_USER_NAME => user.username
        )

        limit.times { expect(limited?).to be(false) }
        expect(limited?).to be(true)
      end

      context 'when enforce_audit_streaming_destination_limits is disabled' do
        before do
          stub_feature_flags(enforce_audit_streaming_destination_limits: false)
        end

        it 'logs the throttled call without blocking it' do
          expect(Gitlab::AuthLogger).to receive(:error).once
            .with(hash_including(env: :audit_event_streaming_destination_mutation_request_limit))

          (limit + 1).times { expect(limited?).to be(false) }
        end
      end
    end
  end
end
