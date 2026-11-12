# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'AnthropicComplianceIntegrationDelete', feature_category: :ai_governance do
  include GraphqlHelpers

  let_it_be(:group) { create(:group, :private) }
  let_it_be(:subgroup) { create(:group, :private, parent: group) }
  let_it_be(:owner) { create(:user, owner_of: group) }
  let_it_be(:maintainer) { create(:user, maintainer_of: group) }

  let_it_be_with_refind(:integration) { create(:ai_compliance_anthropic_integration, namespace: group) }

  let(:target_group) { group }
  let(:current_user) { owner }

  let(:mutation) do
    graphql_mutation(:anthropic_compliance_integration_delete, { group_path: target_group.full_path }, <<~GQL)
      errors
      errorReason
    GQL
  end

  subject(:request) { post_graphql_mutation(mutation, current_user: current_user) }

  def mutation_response
    graphql_mutation_response(:anthropic_compliance_integration_delete)
  end

  context 'when the owner deletes the integration' do
    it 'deletes the integration', :aggregate_failures do
      expect { request }.to change { Ai::Compliance::Anthropic::Integration.count }.by(-1)

      expect(graphql_errors).to be_blank
      expect(mutation_response).to include('errors' => [], 'errorReason' => nil)
    end

    it 'keeps sessions already ingested' do
      anthropic_session = create(:ai_compliance_anthropic_session, namespace: group, anthropic_integration: integration)

      expect { request }.not_to change { Ai::Governance::Session.count }
      expect(Ai::Governance::Session.exists?(anthropic_session.ai_governance_session_id)).to be(true)
    end

    it 'records an audit event' do
      expect(Gitlab::Audit::Auditor).to receive(:audit).with(
        hash_including(name: 'anthropic_compliance_integration_deleted', author: owner, scope: group, target: group)
      ).and_call_original

      request
    end
  end

  context 'when the group has no integration' do
    before do
      Ai::Compliance::Anthropic::Integration.where(namespace: group).delete_all
    end

    it 'returns NOT_FOUND', :aggregate_failures do
      expect(Gitlab::Audit::Auditor).not_to receive(:audit)

      request

      expect(graphql_errors).to be_blank
      expect(mutation_response['errorReason']).to eq('NOT_FOUND')
      expect(mutation_response['errors']).to be_present
    end
  end

  shared_examples 'a refused request' do
    it 'returns a resource-not-available error and keeps the integration', :aggregate_failures do
      expect { request }.not_to change { Ai::Compliance::Anthropic::Integration.count }

      expect_graphql_errors_to_include(Gitlab::Graphql::Authorize::AuthorizeResource::RESOURCE_ACCESS_ERROR)
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

  it_behaves_like 'authorizing granular token permissions for GraphQL', :delete_anthropic_compliance_integration do
    let(:user) { owner }
    let(:boundary_object) { group }
    let(:authz_mutation) do
      graphql_mutation(:anthropic_compliance_integration_delete, { group_path: group.full_path }, 'errors')
    end

    let(:request) { post_graphql_mutation(authz_mutation, token: { personal_access_token: pat }) }
  end
end
