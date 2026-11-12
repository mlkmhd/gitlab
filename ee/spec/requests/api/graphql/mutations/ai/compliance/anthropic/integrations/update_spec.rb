# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'AnthropicComplianceIntegrationUpdate', :clean_gitlab_redis_rate_limiting,
  feature_category: :ai_governance do
  include GraphqlHelpers

  let_it_be(:group) { create(:group, :private) }
  let_it_be(:subgroup) { create(:group, :private, parent: group) }
  let_it_be(:owner) { create(:user, owner_of: group) }
  let_it_be(:maintainer) { create(:user, maintainer_of: group) }

  let_it_be(:stored_key) { 'sk-ant-api01-stored-key' }
  let_it_be_with_refind(:integration) do
    create(:ai_compliance_anthropic_integration, namespace: group, api_key: stored_key, enabled: true)
  end

  let(:new_key) { 'sk-ant-api01-replacement-key' }
  let(:sessions_url) { 'https://api.anthropic.com/v1/compliance/apps/sessions/local' }
  let(:target_group) { group }
  let(:current_user) { owner }
  let(:input) { { api_key: new_key } }

  let(:mutation) do
    graphql_mutation(
      :anthropic_compliance_integration_update,
      { group_path: target_group.full_path, **input },
      <<~GQL
        anthropicComplianceIntegration { enabled disabledReason lastSuccessfulSyncAt updatedAt }
        errors
        errorReason
      GQL
    )
  end

  subject(:request) { post_graphql_mutation(mutation, current_user: current_user) }

  def mutation_response
    graphql_mutation_response(:anthropic_compliance_integration_update)
  end

  def stub_sessions(status:, body: { data: [], next_page: nil }.to_json)
    stub_request(:get, sessions_url).with(query: hash_including({}))
      .to_return(status: status, body: body, headers: { 'Content-Type' => 'application/json' })
  end

  def sessions_request(key = nil)
    request = a_request(:get, sessions_url).with(query: hash_including({}))
    key ? request.with(headers: { 'x-api-key' => key }) : request
  end

  def error_body(type, message = 'error')
    { error: { type: type, message: message } }.to_json
  end

  def expect_audit(message)
    expect(Gitlab::Audit::Auditor).to receive(:audit).with(
      hash_including(
        name: 'anthropic_compliance_integration_updated', author: owner, scope: group, target: group,
        message: message
      )
    ).and_call_original
  end

  shared_examples 'a typed error' do |reason|
    it "returns #{reason} without changing the integration", :aggregate_failures do
      expect { request }.not_to change { integration.reload.attributes }

      expect(graphql_errors).to be_blank
      expect(mutation_response['anthropicComplianceIntegration']).to include(
        'enabled' => integration.reload.enabled,
        'disabledReason' => integration.disabled_reason&.upcase
      )
      expect(mutation_response['errorReason']).to eq(reason)
      expect(mutation_response['errors']).to be_present
      expect(response.body).not_to include(new_key)
      expect(response.body).not_to include(stored_key)
    end

    it 'does not record an audit event' do
      expect(Gitlab::Audit::Auditor).not_to receive(:audit)

      request
    end
  end

  context 'when replacing the key' do
    context 'when Anthropic accepts the new key' do
      before do
        stub_sessions(status: 200)
        integration.update!(enabled: false, disabled_reason: :invalid_key)
      end

      it 'stores the new key and enables the integration', :aggregate_failures do
        request

        expect(graphql_errors).to be_blank
        expect(mutation_response).to include(
          'errors' => [],
          'errorReason' => nil,
          'anthropicComplianceIntegration' => include('enabled' => true, 'disabledReason' => nil)
        )
        expect(integration.reload.api_key).to eq(new_key)
        expect(sessions_request(new_key)).to have_been_made.once
      end

      it 'does not return either key in the response' do
        request

        expect(response.body).not_to include(new_key)
        expect(response.body).not_to include(stored_key)
      end

      it 'records that the key was replaced and the integration enabled' do
        expect_audit('Replaced Anthropic Compliance Access Key')
        expect_audit('Enabled Anthropic Compliance integration')

        request
      end
    end

    context 'when the integration is enabled' do
      before do
        stub_sessions(status: 200)
      end

      it 'records only that the key was replaced' do
        expect_audit('Replaced Anthropic Compliance Access Key')
        expect(Gitlab::Audit::Auditor).not_to receive(:audit)
          .with(hash_including(message: 'Enabled Anthropic Compliance integration'))

        request
      end
    end

    context 'when an owner turned the integration off' do
      before do
        stub_sessions(status: 200)
        integration.update!(enabled: false, disabled_reason: nil)
      end

      it 'stores the new key and keeps the integration off', :aggregate_failures do
        request

        expect(mutation_response).to include(
          'errors' => [],
          'anthropicComplianceIntegration' => include('enabled' => false, 'disabledReason' => nil)
        )
        expect(integration.reload).to have_attributes(api_key: new_key, enabled: false, disabled_reason: nil)
        expect(sessions_request(new_key)).to have_been_made.once
      end

      it 'records only that the key was replaced' do
        expect_audit('Replaced Anthropic Compliance Access Key')
        expect(Gitlab::Audit::Auditor).not_to receive(:audit)
          .with(hash_including(message: 'Enabled Anthropic Compliance integration'))

        request
      end
    end

    context 'when an owner turned the integration off and local sessions are unavailable' do
      before do
        stub_sessions(status: 404, body: error_body('not_found_error', 'Local sessions are not available.'))
        integration.update!(enabled: false, disabled_reason: nil)
      end

      it 'stores the new key and still records that the owner turned it off' do
        request

        expect(integration.reload).to have_attributes(api_key: new_key, enabled: false, disabled_reason: nil)
      end
    end

    context 'when Anthropic rejects the new key' do
      before do
        stub_sessions(status: 401, body: error_body('authentication_error'))
      end

      it_behaves_like 'a typed error', 'INVALID_KEY'
    end

    context 'when Anthropic rate limits the request' do
      before do
        stub_sessions(status: 429, body: error_body('rate_limit_error'))
      end

      it_behaves_like 'a typed error', 'RATE_LIMITED'
    end

    context 'when Anthropic cannot be reached' do
      before do
        stub_sessions(status: 500, body: error_body('api_error'))
      end

      it_behaves_like 'a typed error', 'VERIFICATION_FAILED'
    end

    context 'when the new key is blank' do
      let(:new_key) { '  ' }

      it_behaves_like 'a typed error', 'BLANK_KEY'
    end
  end

  context 'when turning on a disabled integration' do
    let(:input) { { enabled: true } }

    before do
      integration.update!(enabled: false, disabled_reason: :repeated_failures, consecutive_failure_count: 5)
    end

    context 'when Anthropic accepts the stored key' do
      before do
        stub_sessions(status: 200)
      end

      it 're-verifies the stored key and enables the integration', :aggregate_failures do
        request

        expect(mutation_response).to include(
          'errors' => [],
          'errorReason' => nil,
          'anthropicComplianceIntegration' => include('enabled' => true, 'disabledReason' => nil)
        )
        expect(sessions_request(stored_key)).to have_been_made.once
        expect(integration.reload).to have_attributes(api_key: stored_key, consecutive_failure_count: 0)
      end

      it 'records an audit event' do
        expect_audit('Enabled Anthropic Compliance integration')

        request
      end
    end

    context 'when local sessions are unavailable for the Claude organization' do
      before do
        stub_sessions(status: 404, body: error_body('not_found_error', 'Local sessions are not available.'))
      end

      it 'keeps the integration disabled with the reason' do
        request

        expect(mutation_response).to include(
          'errorReason' => nil,
          'anthropicComplianceIntegration' => include(
            'enabled' => false, 'disabledReason' => 'LOCAL_SESSIONS_UNAVAILABLE'
          )
        )
      end

      it 'does not record an audit event' do
        expect(Gitlab::Audit::Auditor).not_to receive(:audit)

        request
      end
    end

    context 'when Anthropic rejects the stored key' do
      before do
        stub_sessions(status: 401, body: error_body('authentication_error'))
      end

      it_behaves_like 'a typed error', 'INVALID_KEY'
    end

    context 'when Anthropic cannot be reached' do
      before do
        stub_sessions(status: 500, body: error_body('api_error'))
      end

      it_behaves_like 'a typed error', 'VERIFICATION_FAILED'
    end
  end

  context 'when turning on an enabled integration' do
    let(:input) { { enabled: true } }

    it 'returns the integration without contacting Anthropic', :aggregate_failures do
      expect(Gitlab::Audit::Auditor).not_to receive(:audit)

      request

      expect(mutation_response).to include(
        'errorReason' => nil, 'anthropicComplianceIntegration' => include('enabled' => true)
      )
      expect(sessions_request).not_to have_been_made
    end
  end

  context 'when turning off the integration' do
    let(:input) { { enabled: false } }

    it 'disables it with no reason without contacting Anthropic', :aggregate_failures do
      request

      expect(mutation_response).to include(
        'errors' => [],
        'errorReason' => nil,
        'anthropicComplianceIntegration' => include('enabled' => false, 'disabledReason' => nil)
      )
      expect(integration.reload).to have_attributes(enabled: false, disabled_reason: nil, api_key: stored_key)
      expect(sessions_request).not_to have_been_made
    end

    it 'clears a reason GitLab set' do
      integration.update!(enabled: false, disabled_reason: :repeated_failures)

      request

      expect(integration.reload.disabled_reason).to be_nil
    end

    it 'records an audit event' do
      expect_audit('Disabled Anthropic Compliance integration')

      request
    end

    context 'when an owner already turned it off' do
      before do
        integration.update!(enabled: false, disabled_reason: nil)
      end

      it 'returns the integration without saving or recording an audit event', :aggregate_failures do
        expect(Gitlab::Audit::Auditor).not_to receive(:audit)

        expect { request }.not_to change { integration.reload.updated_at }

        expect(mutation_response).to include(
          'errors' => [],
          'anthropicComplianceIntegration' => include('enabled' => false, 'disabledReason' => nil)
        )
      end
    end

    it 'is not rate limited' do
      allow(Gitlab::ApplicationRateLimiter).to receive(:throttled?).and_return(true)

      request

      expect(mutation_response['errorReason']).to be_nil
    end

    context 'when the integration cannot be saved' do
      before do
        allow_next_found_instance_of(Ai::Compliance::Anthropic::Integration) do |record|
          allow(record).to receive(:update) do
            record.errors.add(:base, 'cannot be saved')
            false
          end
        end
      end

      it_behaves_like 'a typed error', 'INVALID_INTEGRATION'
    end
  end

  context 'when GitLab rate limits the request' do
    where(:limit_key, :input) do
      [
        [:anthropic_compliance_key_verification_by_group, { api_key: 'sk-ant-api01-replacement-key' }],
        [:anthropic_compliance_key_verification_by_user, { api_key: 'sk-ant-api01-replacement-key' }],
        [:anthropic_compliance_key_verification_by_group, { enabled: true }],
        [:anthropic_compliance_key_verification_by_user, { enabled: true }]
      ]
    end

    with_them do
      before do
        integration.update!(enabled: false)
        allow(Gitlab::ApplicationRateLimiter).to receive(:throttled?).and_call_original
        allow(Gitlab::ApplicationRateLimiter).to receive(:throttled?).with(limit_key, anything).and_return(true)
      end

      it_behaves_like 'a typed error', 'RATE_LIMITED'

      it 'does not contact Anthropic' do
        request

        expect(sessions_request).not_to have_been_made
      end
    end
  end

  context 'when the group has no integration' do
    before do
      Ai::Compliance::Anthropic::Integration.where(namespace: group).delete_all
    end

    it 'returns NOT_FOUND without contacting Anthropic', :aggregate_failures do
      request

      expect(graphql_errors).to be_blank
      expect(mutation_response).to include('anthropicComplianceIntegration' => nil, 'errorReason' => 'NOT_FOUND')
      expect(mutation_response['errors']).to be_present
      expect(sessions_request).not_to have_been_made
    end
  end

  context 'when neither apiKey nor enabled is given' do
    let(:input) { {} }

    it 'returns an argument error' do
      request

      expect_graphql_errors_to_include('One and only one of [apiKey, enabled] arguments is required.')
    end
  end

  context 'when apiKey is explicitly null' do
    let(:input) { { api_key: nil } }

    before do
      integration.update!(enabled: false)
    end

    it 'returns an argument error without re-enabling the integration', :aggregate_failures do
      request

      expect_graphql_errors_to_include('One and only one of [apiKey, enabled] arguments is required.')
      expect(integration.reload.enabled).to be(false)
      expect(sessions_request).not_to have_been_made
    end
  end

  context 'when both apiKey and enabled are given' do
    let(:input) { { api_key: new_key, enabled: false } }

    it 'returns an argument error' do
      request

      expect_graphql_errors_to_include('One and only one of [apiKey, enabled] arguments is required.')
    end
  end

  shared_examples 'a refused request' do
    it 'returns a resource-not-available error and changes nothing', :aggregate_failures do
      expect { request }.not_to change { integration.reload.attributes }

      expect_graphql_errors_to_include(Gitlab::Graphql::Authorize::AuthorizeResource::RESOURCE_ACCESS_ERROR)
      expect(sessions_request).not_to have_been_made
    end
  end

  context 'when the user is a maintainer' do
    let(:current_user) { maintainer }

    it_behaves_like 'a refused request'
  end

  context 'when the user is anonymous' do
    let(:current_user) { nil }

    it_behaves_like 'a refused request'
  end

  context 'when the group is a subgroup' do
    let(:target_group) { subgroup }

    it_behaves_like 'a refused request'
  end

  context 'when the claude_code_compliance_api_ingestion feature flag is disabled' do
    before do
      stub_feature_flags(claude_code_compliance_api_ingestion: false)
    end

    it_behaves_like 'a refused request'
  end

  it_behaves_like 'authorizing granular token permissions for GraphQL', :update_anthropic_compliance_integration do
    let(:user) { owner }
    let(:boundary_object) { group }
    let(:authz_mutation) do
      graphql_mutation(:anthropic_compliance_integration_update,
        { group_path: group.full_path, enabled: false }, 'errors')
    end

    let(:request) { post_graphql_mutation(authz_mutation, token: { personal_access_token: pat }) }
  end
end
