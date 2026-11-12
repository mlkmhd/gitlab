# frozen_string_literal: true

# Needs post_mutation, mutation_response, resource (the project or group being initialized),
# service_class, and create_existing_secrets_manager (a callable). current_user must be
# authorized for the mutation.
RSpec.shared_examples 'a rate limited secrets manager initialize mutation' do
  before do
    allow(::Gitlab::ApplicationRateLimiter).to receive(:throttled?).and_call_original
  end

  it 'counts the request against the top-level group' do
    post_mutation

    expect(::Gitlab::ApplicationRateLimiter).to have_received(:throttled?)
      .with(:secrets_manager_initialize, scope: { namespace: resource.root_ancestor })
  end

  context 'when the top-level group is throttled' do
    before do
      allow(::Gitlab::ApplicationRateLimiter).to receive(:throttled?)
        .with(:secrets_manager_initialize, scope: { namespace: resource.root_ancestor }).and_return(true)
    end

    it 'returns a payload error without initializing the secrets manager', :aggregate_failures do
      expect(service_class).not_to receive(:new)

      post_mutation

      expect(graphql_errors).to be_nil
      expect(mutation_response['errors']).to contain_exactly(::Gitlab::ApplicationRateLimiter.throttled_error_message)
      expect(resource.reload.secrets_manager).to be_nil
    end
  end

  # A request that is rejected before the count must not use up the top-level group's quota.
  context 'when the request is rejected before the rate limit check' do
    shared_examples 'a request that is not counted' do
      it 'does not count the request' do
        post_mutation

        expect(::Gitlab::ApplicationRateLimiter).not_to have_received(:throttled?)
          .with(:secrets_manager_initialize, anything)
      end
    end

    context 'when the user is not authorized' do
      let(:current_user) { create(:user) }

      it_behaves_like 'a request that is not counted'
    end

    context 'when the namespace is inactive' do
      before do
        if resource.is_a?(Group)
          resource.namespace_settings.update!(archived: true)
        else
          resource.update!(archived: true)
        end
      end

      it_behaves_like 'a request that is not counted'
    end

    context 'when the entitlement denies writes' do
      before do
        allow(SecretsManagement::Entitlement).to receive(:for)
          .and_return(SecretsManagement::Entitlement.new(state: :ineligible))
      end

      it_behaves_like 'a request that is not counted'
    end
  end

  context 'when the resource already has a secrets manager' do
    before do
      create_existing_secrets_manager.call
    end

    it 'does not count the request', :aggregate_failures do
      post_mutation

      expect(::Gitlab::ApplicationRateLimiter).not_to have_received(:throttled?)
        .with(:secrets_manager_initialize, anything)
      expect(mutation_response['errors']).to include(a_string_including('already initialized'))
    end
  end
end
