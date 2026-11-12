# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Ai::ToolRules::McpCallerSurface, feature_category: :ai_agents do
  let_it_be(:group) { create(:group) }
  let_it_be(:project) { create(:project, group: group) }
  let_it_be(:user) { create(:user, developer_of: project) }
  let_it_be(:auth_response) { Ai::UserAuthorizable::Response.new(allowed?: true, namespace_ids: [group.id]) }

  let(:environment) { :web }
  let(:workflow_definition) { 'chat' }
  let(:workflow) do
    create(:duo_workflows_workflow, project: project, user: user, workflow_definition: workflow_definition,
      environment: environment)
  end

  let(:scopes) { ['ai_workflows', 'mcp', "duo_workflow:#{workflow.id}"] }
  let(:access_token) { instance_double(OauthAccessToken, scopes: Doorkeeper::OAuth::Scopes.from_array(scopes)) }

  subject(:surface) { described_class.for(access_token, user) }

  before do
    allow(::Gitlab::Llm::StageCheck).to receive(:available?).and_return(true)
    allow_any_instance_of(User).to receive(:allowed_to_use).and_return(auth_response) # rubocop:disable RSpec/AnyInstanceOf -- Ability loads its own copy of the user
    project.project_setting.update!(duo_features_enabled: true)
  end

  context 'when the token names no workflow' do
    let(:scopes) { %w[ai_workflows mcp] }

    it { is_expected.to eq(::Ai::ToolRules::GovernanceSurface::LOCAL) }
  end

  context 'without an access token' do
    let(:access_token) { nil }

    it { is_expected.to eq(::Ai::ToolRules::GovernanceSurface::LOCAL) }
  end

  context 'when the token is bound to Agentic Chat in the GitLab UI' do
    it { is_expected.to eq(:web) }
  end

  context 'when the session token is a stateless access token', :clean_gitlab_redis_shared_state do
    let_it_be(:cloud_connector_key) { create(:cloud_connector_keys) }
    let_it_be(:organization) { create(:organization) }

    let(:access_token) do
      issued = Authn::Tokens::StatelessAccessToken.issue(user: user, organization: organization, ttl: 1.hour.to_i,
        scopes: scopes)

      Authn::Tokens::StatelessAccessToken.from_jwt(issued.plaintext_token)
    end

    before do
      allow(::CloudConnector::CachingKeyLoader).to receive(:private_jwk).and_return(cloud_connector_key.to_jwk)
      allow(::CloudConnector::Keys).to receive(:valid).and_return([cloud_connector_key])
      allow(Doorkeeper::OpenidConnect.configuration).to receive(:issuer).and_return('http://test.host/oauth-issuer')
    end

    it 'reads the binding from its scopes' do
      expect(access_token).to be_a(Authn::Tokens::StatelessAccessToken)
      expect(surface).to eq(:web)
    end
  end

  context 'when the token is bound to a local session' do
    let(:environment) { :chat }

    it { is_expected.to eq(:chat) }
  end

  context 'when the token is bound to a Developer Flow running in the background' do
    let(:workflow_definition) { 'developer/v1' }
    let(:environment) { :ambient }

    it { is_expected.to eq(::Ai::ToolRules::GovernanceSurface::BACKGROUND) }

    context 'when background governance is off' do
      before do
        stub_feature_flags(duo_workflow_background_tool_governance: false)
      end

      it { is_expected.to eq(:ambient) }
    end
  end

  context 'when the bound workflow has no environment' do
    let(:environment) { nil }

    it { is_expected.to eq(::Ai::ToolRules::GovernanceSurface::LOCAL) }
  end

  context 'when the bound workflow was deleted' do
    let(:scopes) { ["duo_workflow:#{non_existing_record_id}"] }

    it { is_expected.to eq(::Ai::ToolRules::GovernanceSurface::REFUSED) }
  end

  context 'when the user cannot read the bound workflow' do
    let(:workflow) do
      create(:duo_workflows_workflow, project: create(:project, :private), workflow_definition: 'developer/v1',
        environment: :web)
    end

    it { is_expected.to eq(::Ai::ToolRules::GovernanceSurface::REFUSED) }
  end

  context 'when the workflow scope is malformed' do
    let(:scopes) { %w[mcp duo_workflow:abc] }

    it { is_expected.to eq(::Ai::ToolRules::GovernanceSurface::REFUSED) }
  end

  context 'when a malformed workflow scope sits beside a valid one' do
    let(:scopes) { ['mcp', "duo_workflow:#{workflow.id}", 'duo_workflow:abc'] }

    it { is_expected.to eq(::Ai::ToolRules::GovernanceSurface::REFUSED) }
  end

  context 'when the token names two workflows' do
    let(:scopes) { ['mcp', "duo_workflow:#{workflow.id}", "duo_workflow:#{workflow.id + 1}"] }

    it { is_expected.to eq(::Ai::ToolRules::GovernanceSurface::REFUSED) }
  end

  describe 'logging a refusal' do
    let(:logger) { instance_double(Gitlab::Mcp::Logger, conditional_info: nil) }

    before do
      allow(Gitlab::Mcp::Logger).to receive(:build).and_return(logger)
    end

    def expect_refusal_logged(workflow_id:, reason:)
      surface

      expect(logger).to have_received(:conditional_info).with(
        user,
        message: 'MCP session refused',
        event_name: 'session_refused',
        ai_component: 'mcp_server',
        ::Labkit::Fields::DUO_WORKFLOW_ID => workflow_id,
        refusal_reason: reason
      )
    end

    context 'when the bound workflow was deleted' do
      let(:scopes) { ["duo_workflow:#{non_existing_record_id}"] }

      it 'logs the workflow ID and that it was not found' do
        expect_refusal_logged(workflow_id: non_existing_record_id, reason: 'workflow_not_found')
      end
    end

    context 'when the user cannot read the bound workflow' do
      let(:workflow) do
        create(:duo_workflows_workflow, project: create(:project, :private), workflow_definition: 'developer/v1',
          environment: :web)
      end

      it 'logs the workflow ID and that it was not readable' do
        expect_refusal_logged(workflow_id: workflow.id, reason: 'workflow_not_readable')
      end
    end

    context 'when the workflow scope is malformed' do
      let(:scopes) { %w[mcp duo_workflow:abc] }

      it 'logs that the scope names no workflow' do
        expect_refusal_logged(workflow_id: nil, reason: 'invalid_workflow_scope')
      end
    end

    context 'when the session resolves' do
      it 'logs nothing' do
        surface

        expect(logger).not_to have_received(:conditional_info)
      end
    end
  end
end
