# frozen_string_literal: true

require 'spec_helper'

RSpec.describe API::Ai::DuoWorkflows::WorkflowsInternal, 'GET /ai/duo_workflows/workflows/:id/catalog_items',
  :aggregate_failures, feature_category: :ai_catalog_curation do
  include_context 'workhorse headers'

  let_it_be(:group) { create(:group) }
  let_it_be(:project) { create(:project, group: group) }
  let_it_be(:user) { create(:user, maintainer_of: project) }

  let_it_be_with_reload(:flow) { create(:ai_catalog_flow, :public, project: project) }
  let_it_be(:item_version) do
    create(:ai_catalog_flow_version, :released, item: flow, version: '1.0.0')
  end

  let_it_be_with_reload(:agent) { create(:ai_catalog_agent, :public, project: project) }
  let_it_be_with_reload(:agent_version) do
    create(:ai_catalog_agent_version, :released, item: agent, version: '2.0.0')
  end

  let_it_be(:dependency) do
    create(:ai_catalog_item_version_dependency,
      ai_catalog_item_version: item_version, dependency: agent, dependency_version: agent_version)
  end

  let_it_be_with_reload(:workflow) do
    create(:duo_workflows_workflow, user: user, project: project, ai_catalog_item_version: item_version)
  end

  let(:path) { "/ai/duo_workflows/workflows/#{workflow.id}/catalog_items" }

  before do
    stub_application_setting(instance_level_ai_beta_features_enabled: true)
    allow(::Gitlab::Llm::StageCheck).to receive(:available?).with(project, :duo_workflow).and_return(true)
    allow_any_instance_of(User).to receive_messages(allowed_to_use?: true, allowed_to_use_for_resource?: true) # rubocop:disable RSpec/AnyInstanceOf -- not the next instance
  end

  it 'returns the flow and its resolved agents' do
    get api(path, user), headers: workhorse_headers

    expect(response).to have_gitlab_http_status(:ok)
    expect(json_response['schema_version']).to eq(1)
    expect(json_response['item']).to include(
      'item_type' => 'flow', 'item_id' => flow.id.to_s, 'version' => '1.0.0', 'definition_kind' => 'inline',
      'sub_items_skipped_reason' => nil
    )
    expect(json_response['item']['sub_items']).to contain_exactly(
      a_hash_including(
        'item_type' => 'agent',
        'item_id' => agent.id.to_s,
        'version' => '2.0.0',
        'definition' => a_hash_including('prompt' => 'Talk like a pirate!', 'mcp_tools' => [])
      )
    )
  end

  it 'returns a refused agent with an error node and without its name' do
    allow(Ability).to receive(:allowed?).and_call_original
    allow(Ability).to receive(:allowed?).with(user, :read_ai_catalog_item, agent).and_return(false)

    get api(path, user), headers: workhorse_headers

    expect(response).to have_gitlab_http_status(:ok)
    sub_item = json_response['item']['sub_items'].first
    expect(sub_item['error']).to include('code' => 'unknown_item')
    expect(sub_item.keys).to contain_exactly('item_type', 'item_id', 'version', 'error')
  end

  it 'returns 404 when the user can no longer read the flow' do
    allow(Ability).to receive(:allowed?).and_call_original
    allow(Ability).to receive(:allowed?).with(user, :read_ai_catalog_item, flow).and_return(false)

    get api(path, user), headers: workhorse_headers

    expect(response).to have_gitlab_http_status(:not_found)
  end

  it 'returns 422 when the workflow runs no saved catalog flow' do
    plain_workflow = create(:duo_workflows_workflow, user: user, project: project)

    get api("/ai/duo_workflows/workflows/#{plain_workflow.id}/catalog_items", user), headers: workhorse_headers

    expect(response).to have_gitlab_http_status(:unprocessable_entity)
  end

  it 'returns 404 for a workflow the user does not own' do
    other_user = create(:user, maintainer_of: project)
    other_workflow = create(:duo_workflows_workflow, user: other_user, project: project,
      ai_catalog_item_version: item_version)

    get api("/ai/duo_workflows/workflows/#{other_workflow.id}/catalog_items", user), headers: workhorse_headers

    expect(response).to have_gitlab_http_status(:not_found)
  end

  it 'returns 403 without the Workhorse header' do
    get api(path, user)

    expect(response).to have_gitlab_http_status(:forbidden)
  end

  it 'returns 401 without a user' do
    get api(path), headers: workhorse_headers

    expect(response).to have_gitlab_http_status(:unauthorized)
  end

  context 'with an ai_workflows scoped OAuth token' do
    let_it_be(:oauth_token) { create(:oauth_access_token, user: user, scopes: [:ai_workflows]) }

    it 'is allowed' do
      get api(path, oauth_access_token: oauth_token), headers: workhorse_headers

      expect(response).to have_gitlab_http_status(:ok)
    end
  end

  context 'with a token that lacks the scope' do
    let_it_be(:token) { create(:personal_access_token, user: user, scopes: [:read_user]) }

    it 'returns 403' do
      get api(path, personal_access_token: token), headers: workhorse_headers

      expect(response).to have_gitlab_http_status(:forbidden)
    end
  end

  it 'returns 404 for a workflow id that does not exist' do
    get api('/ai/duo_workflows/workflows/0/catalog_items', user), headers: workhorse_headers

    expect(response).to have_gitlab_http_status(:not_found)
  end

  it 'returns 422 when the flow version was removed under a running session' do
    workflow.update_column(:ai_catalog_item_version_id, nil)

    get api(path, user), headers: workhorse_headers

    expect(response).to have_gitlab_http_status(:unprocessable_entity)
  end

  context 'when the feature flag is off' do
    before do
      stub_feature_flags(ai_catalog_flow_agent_references: false)
    end

    it 'returns the flow with no sub_items and the reason' do
      get api(path, user), headers: workhorse_headers

      expect(response).to have_gitlab_http_status(:ok)
      expect(json_response['item']['sub_items']).to be_empty
      expect(json_response['item']['sub_items_skipped_reason']).to eq('feature_flag_disabled')
    end
  end
end
