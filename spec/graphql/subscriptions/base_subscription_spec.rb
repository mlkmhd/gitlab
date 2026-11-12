# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Subscriptions::BaseSubscription, feature_category: :system_access do
  include GraphqlHelpers

  describe '#initialize' do
    let(:context) do
      query = GraphQL::Query.new(empty_schema, document: nil, context: {}, variables: {})

      GraphQL::Query::Context.new(
        query: query,
        values: { current_user: current_user, access_token: access_token }
      )
    end

    subject(:build_subscription) { resolver_instance(described_class, ctx: context) }

    context 'when current_user and access_token are present' do
      let(:current_user) { instance_double(User) }
      let(:access_token) { instance_double(PersonalAccessToken) }

      it 'resets both so stale membership or token scope is not used for authorization' do
        expect(current_user).to receive(:reset)
        expect(access_token).to receive(:reset)

        build_subscription
      end
    end

    context 'when current_user is nil' do
      let(:current_user) { nil }
      let(:access_token) { instance_double(PersonalAccessToken) }

      it 'does not attempt to reset the user' do
        expect(access_token).to receive(:reset)

        expect { build_subscription }.not_to raise_error
      end
    end

    context 'when access_token is nil' do
      let(:current_user) { instance_double(User) }
      let(:access_token) { nil }

      it 'resets the user and does not attempt to reset the token' do
        expect(current_user).to receive(:reset)

        expect { build_subscription }.not_to raise_error
      end
    end

    context 'when access_token does not respond to reset' do
      let(:current_user) { instance_double(User) }
      let(:access_token) { Object.new }

      it 'does not attempt to reset the token' do
        expect(current_user).to receive(:reset)

        expect { build_subscription }.not_to raise_error
      end
    end
  end

  describe '.rate_limit' do
    let(:subscription_class) { Class.new(described_class) }
    let(:object) { instance_double(Project, id: 1) }

    it 'has no policy without a declared rate limit' do
      expect(subscription_class.rate_limit_policy).to be_nil
    end

    context 'with a declared rate limit' do
      before do
        subscription_class.rate_limit(:ci_pipeline_statuses_subscription,
          scope: ->(_args, project) { { project: project } })
      end

      it 'checks the limit with the scope built from the trigger' do
        expect(Gitlab::ApplicationRateLimiter).to receive(:throttled?)
          .with(:ci_pipeline_statuses_subscription, scope: { project: object })
          .and_return(true)

        expect(subscription_class.rate_limit_policy.throttled?({}, object)).to be(true)
      end

      it 'is inherited by a subclass' do
        expect(Class.new(subscription_class).rate_limit_policy).to be(subscription_class.rate_limit_policy)
      end

      it 'is not changed by a subclass that declares its own limit' do
        policy = subscription_class.rate_limit_policy

        Class.new(subscription_class).rate_limit(:ci_job_processed_subscription, scope: ->(_args, _object) { {} })

        expect(subscription_class.rate_limit_policy).to be(policy)
      end

      it 'is not set on the base class' do
        expect(described_class.rate_limit_policy).to be_nil
      end
    end
  end
end
