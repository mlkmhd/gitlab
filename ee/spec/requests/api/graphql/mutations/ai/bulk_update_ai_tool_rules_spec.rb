# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'BulkUpdateAiToolRules', :clean_gitlab_redis_rate_limiting, feature_category: :ai_agents do
  include GraphqlHelpers

  let_it_be(:namespace) { create(:group) }
  let_it_be(:owner) { create(:user, owner_of: namespace) }
  let_it_be(:project) { create(:project, namespace: namespace) }

  let(:params) do
    {
      full_path: namespace.full_path,
      tool_rules: [{ tool_id: 'create_issue', web_access: 'ASK' }]
    }
  end

  let(:mutation) do
    graphql_mutation(
      :bulk_update_ai_tool_rules,
      params,
      <<~GQL
        results {
          toolId
          toolRule {
            webAccess
          }
        }
        errors
      GQL
    )
  end

  before do
    ::Ai::ToolRules::Registry.instance_variable_set(:@all_tool_names, nil)
    ::Ai::ToolRules::Registry.instance_variable_set(:@catalog_tool_names, nil)
    ::Ai::ToolRules::Registry.instance_variable_set(:@action_type_for, nil)
    allow(Gitlab::Audit::Auditor).to receive(:audit)
  end

  subject(:request) { post_graphql_mutation(mutation, current_user: owner) }

  describe 'rate limiting' do
    let_it_be(:other_owner) { create(:user, owner_of: namespace) }

    let(:current_user) { owner }

    context 'when the ai_tool_rules_bulk_update_rate_limit feature flag is enabled' do
      it_behaves_like 'rate limited endpoint', rate_limit_key: :ai_tool_rules_bulk_update, graphql: true do
        def request
          post_graphql_mutation(mutation, current_user: current_user)
        end

        def request_with_second_scope
          post_graphql_mutation(mutation, current_user: other_owner)
        end
      end
    end

    context 'when the ai_tool_rules_bulk_update_rate_limit feature flag is disabled' do
      before do
        stub_feature_flags(ai_tool_rules_bulk_update_rate_limit: false)
      end

      it_behaves_like 'unthrottled endpoint', rate_limit_key: :ai_tool_rules_bulk_update, graphql: true do
        def request
          post_graphql_mutation(mutation, current_user: current_user)
        end
      end
    end
  end

  it 'bulk updates tool rules and returns no errors', :aggregate_failures do
    request

    expect(response).to have_gitlab_http_status(:success)
    expect(graphql_errors).to be_blank
    expect(graphql_data_at(:bulk_update_ai_tool_rules, :errors)).to be_empty
    expect(graphql_data_at(:bulk_update_ai_tool_rules, :results)).to be_present
  end

  context 'when the same mutation is sent twice' do
    before do
      post_graphql_mutation(mutation, current_user: owner)
    end

    it 'writes no audit event the second time and returns the stored rule', :aggregate_failures do
      expect(Gitlab::Audit::Auditor).not_to receive(:audit)

      expect { request }.not_to change { Ai::ToolRule.where(namespace_id: namespace.id).pluck(:id, :updated_at) }

      expect(response).to have_gitlab_http_status(:success)
      expect(graphql_data_at(:bulk_update_ai_tool_rules, :errors)).to be_empty
      expect(graphql_data_at(:bulk_update_ai_tool_rules, :results)).to contain_exactly(
        a_hash_including('toolId' => 'create_issue', 'toolRule' => a_hash_including('webAccess' => 'ASK'))
      )
    end
  end

  context 'with a GitLab MCP server tool' do
    let(:input) do
      {
        full_path: namespace.full_path,
        tool_rules: [
          { tool_id: 'create_issue', web_access: :ASK },
          { tool_id: 'search', web_access: :DENY }
        ]
      }
    end

    let(:mutation) do
      graphql_mutation(:bulk_update_ai_tool_rules, input,
        'errors results { toolId errors toolRule { actionType category source } }')
    end

    context 'when MCP governance is inactive' do
      before do
        stub_feature_flags(duo_mcp_tool_governance: false)
      end

      it 'rejects only the MCP entry and still saves the catalog one' do
        request

        results = graphql_mutation_response(:bulk_update_ai_tool_rules)['results']
        expect(results.find { |r| r['toolId'] == 'create_issue' }['errors']).to be_empty
        expect(results.find { |r| r['toolId'] == 'search' }['errors'])
          .to include(/search is not a known tool name/)
      end
    end

    context 'when MCP governance is active' do
      before do
        mcp_tools = instance_double(::Ai::ToolRules::GovernedMcpTools, empty?: false, rulable_names: ['search'])
        allow(mcp_tools).to receive(:action_type_for).with('search').and_return(:read)
        allow(::Ai::ToolRules::GovernedMcpTools).to receive(:for).and_return(mcp_tools)
      end

      it 'saves both entries and populates every non-null field for the MCP one' do
        request

        results = graphql_mutation_response(:bulk_update_ai_tool_rules)['results']
        mcp_result = results.find { |r| r['toolId'] == 'search' }

        expect(mcp_result['errors']).to be_empty
        expect(mcp_result['toolRule']).to include(
          'actionType' => 'READ', 'category' => 'MCP', 'source' => 'MCP'
        )
      end

      it 'persists the MCP source on the upserted row' do
        request

        expect(::Ai::ToolRule.find_by(namespace: namespace, tool_name: 'search').tool_source).to eq('mcp')
      end
    end
  end

  context 'with a group boundary' do
    it_behaves_like 'authorizing granular token permissions for GraphQL', :update_ai_tool_rule do
      let(:user) { owner }
      let(:boundary_object) { namespace }
      let(:authz_mutation) do
        graphql_mutation(
          :bulk_update_ai_tool_rules,
          { full_path: namespace.full_path, tool_rules: [{ tool_id: 'create_issue', web_access: 'ASK' }] },
          'errors'
        )
      end

      let(:request) { post_graphql_mutation(authz_mutation, token: { personal_access_token: pat }) }
    end
  end

  context 'with a project boundary' do
    it_behaves_like 'authorizing granular token permissions for GraphQL', :update_ai_tool_rule do
      let(:user) { owner }
      let(:boundary_object) { project }
      let(:authz_mutation) do
        graphql_mutation(
          :bulk_update_ai_tool_rules,
          {
            full_path: project.root_ancestor.full_path,
            project_path: project.full_path,
            tool_rules: [{ tool_id: 'create_issue', web_access: 'ASK' }]
          },
          'errors'
        )
      end

      let(:request) { post_graphql_mutation(authz_mutation, token: { personal_access_token: pat }) }
    end
  end
end
