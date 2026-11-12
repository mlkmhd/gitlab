# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Resolvers::PagesDeploymentsResolver, feature_category: :pages do
  include GraphqlHelpers

  let_it_be(:user) { create(:user) }
  let_it_be(:project) { create(:project, :public) }
  let_it_be(:pages_deployment) { create(:pages_deployment, project: project) }

  def resolve_deployments(current_user:, request: nil)
    resolve(described_class, obj: project, ctx: { current_user: current_user, request: request })
  end

  describe '#resolve' do
    context 'without a request in the context, as in GraphqlChannel' do
      it 'checks the user rate limit without a request' do
        expect(::Gitlab::ApplicationRateLimiter).to receive(:throttled?)
          .with(:pages_deployments_api, scope: { user: user }).and_return(false)

        expect(resolve_deployments(current_user: user).items).to contain_exactly(pages_deployment)
      end

      it 'checks the unauthenticated rate limit by the ActionCable IP address' do
        expect(::Gitlab::ApplicationRateLimiter).to receive(:throttled?)
          .with(:pages_deployments_api_unauthenticated, scope: { ip: '1.2.3.4' }).and_return(false)

        result = ::Gitlab::IpAddressState.with('1.2.3.4') { resolve_deployments(current_user: nil) }

        expect(result.items).to contain_exactly(pages_deployment)
      end

      it 'treats an unauthenticated caller with no IP address as throttled' do
        expect(::Gitlab::ApplicationRateLimiter).not_to receive(:throttled?)

        expect_graphql_error_to_be_created(Gitlab::Graphql::Errors::ResourceNotAvailable) do
          resolve_deployments(current_user: nil)
        end
      end
    end
  end
end
