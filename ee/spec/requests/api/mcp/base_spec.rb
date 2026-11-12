# frozen_string_literal: true

require 'spec_helper'

RSpec.describe API::Mcp::Base, feature_category: :mcp_server do
  using RSpec::Parameterized::TableSyntax

  let_it_be_with_refind(:user) { create(:user) }
  let_it_be(:access_token) { create(:oauth_access_token, user: user, scopes: [:mcp]) }

  def expect_tool_denied(tool_name)
    expect(response).to have_gitlab_http_status(:ok)
    expect(json_response['error']).to be_nil
    expect(json_response.dig('result', 'isError')).to be(true)
    expect(json_response.dig('result', 'content', 0, 'text')).to start_with("#{tool_name} is denied")
  end

  def expect_session_refused(tool_name)
    expect(response).to have_gitlab_http_status(:ok)
    expect(json_response['error']).to be_nil
    expect(json_response.dig('result', 'isError')).to be(true)
    expect(json_response.dig('result', 'content', 0, 'text'))
      .to eq("#{tool_name} is refused because its Duo session's workflow can't be resolved.")
  end

  describe 'POST /mcp' do
    context 'when gitlab.com', :saas do
      let_it_be(:group) { create(:group_with_plan, plan: :ultimate_plan, developers: user) }

      before do
        stub_saas_features(mcp_server_saas_only: true)
      end

      context 'when a root group has mcp_server_enabled' do
        before do
          group.namespace_settings.reload.update!(mcp_server_enabled: true)
        end

        it 'ignores the instance-level mcp_server_enabled setting' do
          stub_application_setting(mcp_server_enabled: false)

          post api('/mcp', user, oauth_access_token: access_token),
            params: { jsonrpc: '2.0', method: 'initialize', id: '1', params: { protocolVersion: '2025-06-18' } }

          expect(response).to have_gitlab_http_status(:ok)
        end
      end

      context 'when no root group has mcp_server_enabled' do
        before do
          group.namespace_settings.reload.update!(mcp_server_enabled: false)
        end

        it 'returns forbidden' do
          post api('/mcp', user, oauth_access_token: access_token),
            params: { jsonrpc: '2.0', method: 'initialize', id: '1', params: { protocolVersion: '2025-06-18' } }

          expect(response).to have_gitlab_http_status(:forbidden)
          expect(json_response['message']).to eq('403 Forbidden - MCP server not enabled for any of your groups')
        end
      end
    end

    context 'when not gitlab.com' do
      let_it_be(:group) { create(:group, developers: user) }

      context 'when Gitlab::CurrentSettings.mcp_server_enabled is true' do
        before do
          stub_application_setting(mcp_server_enabled: true)
        end

        it 'returns ok' do
          post api('/mcp', user, oauth_access_token: access_token),
            params: { jsonrpc: '2.0', method: 'initialize', id: '1', params: { protocolVersion: '2025-06-18' } }

          expect(response).to have_gitlab_http_status(:ok)
        end
      end

      context 'when Gitlab::CurrentSettings.mcp_server_enabled is false' do
        before do
          stub_application_setting(mcp_server_enabled: false)
        end

        it 'returns forbidden' do
          post api('/mcp', user, oauth_access_token: access_token),
            params: { jsonrpc: '2.0', method: 'initialize', id: '1', params: { protocolVersion: '2025-06-18' } }

          expect(response).to have_gitlab_http_status(:forbidden)
          expect(json_response['message']).to eq('403 Forbidden - MCP server disabled for this instance')
        end
      end
    end

    context 'when logging the denial reason' do
      let_it_be(:group) { create(:group, :with_mcp_server_disabled, developers: user) }

      def expect_denial_reason(reason)
        expect_next_instance_of(Gitlab::Mcp::Logger) do |logger|
          expect(logger).to receive(:info).with(
            message: 'MCP server not available',
            event_name: 'permission_denied',
            ai_component: 'mcp_server',
            denial_reason: reason,
            Labkit::Fields::GL_USER_ID => user.id
          )
        end

        post api('/mcp', user, oauth_access_token: access_token),
          params: { jsonrpc: '2.0', method: 'initialize', id: '1', params: { protocolVersion: '2025-11-25' } }
      end

      context 'on gitlab.com with no enabled namespace', :saas do
        before do
          stub_saas_features(mcp_server_saas_only: true)
        end

        it 'logs :no_enabled_namespace' do
          expect_denial_reason(:no_enabled_namespace)
        end

        it 'tracks :no_enabled_namespace' do
          expect do
            post api('/mcp', user, oauth_access_token: access_token),
              params: { jsonrpc: '2.0', method: 'initialize', id: '1', params: { protocolVersion: '2025-11-25' } },
              headers: { 'User-Agent' => 'Cursor/1.2.3' }
          end.to trigger_internal_events('deny_mcp_server_access').with(
            category: 'InternalEventTracking',
            user: user,
            additional_properties: {
              denial_reason: 'no_enabled_namespace',
              oauth_application_id: access_token.application_id,
              mcp_client_name: 'Cursor',
              mcp_client_version: '1.2.3'
            }
          )
        end
      end
    end

    context 'when the project that denies the tool is one the caller cannot read' do
      let_it_be(:public_group) { create(:group, :public) }
      let_it_be(:hidden_project) { create(:project, :private, group: public_group) }
      let(:tool_name) { 'get_work_item_types' }

      before do
        stub_feature_flags(duo_mcp_server_governance_rule_enforcement: public_group)
        create(:ai_tool_rule, namespace: public_group, project: hidden_project,
          tool_name: tool_name, local_access: :deny)
      end

      it 'refuses without naming the project' do
        post api('/mcp', user, oauth_access_token: access_token),
          params: {
            jsonrpc: '2.0', method: 'tools/call', id: '12',
            params: { name: tool_name, arguments: { group_id: public_group.id.to_s } }
          }

        expect_tool_denied(tool_name)
        expect(json_response.dig('result', 'content', 0, 'text'))
          .to eq("#{tool_name} is denied by an Always Deny rule.")
      end
    end

    context 'when only a project inside the named group denies the tool' do
      let_it_be(:parent_group) { create(:group, developers: user) }
      let_it_be(:subgroup) { create(:group, parent: parent_group) }
      let_it_be(:ruled_project) { create(:project, group: subgroup) }
      let(:tool_name) { 'get_work_item_types' }

      before do
        stub_feature_flags(duo_mcp_server_governance_rule_enforcement: parent_group)
      end

      def call_group_tool
        post api('/mcp', user, oauth_access_token: access_token),
          params: {
            jsonrpc: '2.0', method: 'tools/call', id: '9',
            params: { name: tool_name, arguments: { group_id: parent_group.id.to_s } }
          }
      end

      it 'refuses a call that names only the group' do
        create(:ai_tool_rule, namespace: parent_group, project: ruled_project,
          tool_name: tool_name, local_access: :deny)

        call_group_tool

        expect_tool_denied(tool_name)
      end

      it 'names the project that denied it when the caller can read it' do
        create(:ai_tool_rule, namespace: parent_group, project: ruled_project,
          tool_name: tool_name, local_access: :deny)

        call_group_tool

        expect(json_response.dig('result', 'content', 0, 'text')).to eq(
          "#{tool_name} is denied by an Always Deny rule in #{ruled_project.full_path}."
        )
      end

      it 'serves the call when no project underneath denies it' do
        call_group_tool

        expect(response).to have_gitlab_http_status(:ok)
        expect(json_response['error']).to be_nil
        expect(json_response.dig('result', 'isError')).to be(false)
      end
    end

    context 'when only the epic named by epic_id denies the tool' do
      let_it_be(:epic_group) { create(:group, developers: user) }
      let_it_be(:plain_group) { create(:group, developers: user) }
      let_it_be(:plain_project) { create(:project, group: plain_group) }
      let_it_be(:epic) { create(:epic, group: epic_group) }

      before do
        stub_feature_flags(duo_mcp_server_governance_rule_enforcement: epic_group)
        create(:ai_tool_rule, namespace: epic_group, tool_name: 'create_issue', local_access: :deny)
      end

      def create_issue_with(arguments)
        post api('/mcp', user, oauth_access_token: access_token),
          params: {
            jsonrpc: '2.0', method: 'tools/call', id: '11',
            params: { name: 'create_issue', arguments: arguments }
          }
      end

      it 'refuses even though the project named is somewhere else' do
        create_issue_with({ id: plain_project.full_path, title: 'anything', epic_id: epic.id })

        expect_tool_denied('create_issue')
      end
    end

    context 'when only the fork target named by namespace_path denies the tool' do
      let_it_be(:target_group) { create(:group, developers: user) }
      let_it_be(:source_group) { create(:group, developers: user) }
      let_it_be(:source_project) { create(:project, :public, group: source_group) }

      before do
        stub_feature_flags(duo_mcp_server_governance_rule_enforcement: target_group)
        create(:ai_tool_rule, namespace: target_group, tool_name: 'fork_repository', local_access: :deny)
      end

      it 'refuses a URL-encoded path, decoded the same way the endpoint decodes it' do
        post api('/mcp', user, oauth_access_token: access_token),
          params: {
            jsonrpc: '2.0', method: 'tools/call', id: '12',
            params: {
              name: 'fork_repository',
              arguments: { id: source_project.full_path, namespace_path: ERB::Util.url_encode(target_group.full_path) }
            }
          },
          as: :json

        expect_tool_denied('fork_repository')
      end
    end

    context 'when only the namespace a project is created in denies the tool' do
      let_it_be(:governed_group) { create(:group, maintainers: user) }
      let_it_be(:target_group) { create(:group, parent: governed_group) }
      let_it_be(:other_group) { create(:group, maintainers: user) }

      before do
        stub_feature_flags(duo_mcp_server_governance_rule_enforcement: governed_group)
        create(:ai_tool_rule, namespace: governed_group, tool_name: 'save_project', local_access: :deny)
      end

      def save_project(arguments)
        post api('/mcp', user, oauth_access_token: access_token),
          params: {
            jsonrpc: '2.0', method: 'tools/call', id: '14',
            params: { name: 'save_project', arguments: arguments }
          },
          as: :json
      end

      it 'refuses a namespace_id naming that group', :aggregate_failures do
        save_project(name: 'denied-by-id', namespace_id: target_group.id)

        expect_tool_denied('save_project')
        expect(Project.find_by_full_path("#{target_group.full_path}/denied-by-id")).to be_nil
      end

      it 'refuses a URL-encoded namespace_path naming that group', :aggregate_failures do
        save_project(name: 'denied-by-path', namespace_path: ERB::Util.url_encode(target_group.full_path))

        expect_tool_denied('save_project')
        expect(Project.find_by_full_path("#{target_group.full_path}/denied-by-path")).to be_nil
      end

      it 'still creates the project in a group without the rule', :aggregate_failures do
        save_project(name: 'allowed', namespace_id: other_group.id)

        expect(response).to have_gitlab_http_status(:ok)
        expect(json_response['result']['isError']).to be_falsey
        expect(Project.find_by_full_path("#{other_group.full_path}/allowed")).to be_present
      end
    end

    context 'when a url is parsed differently from a plain path' do
      let_it_be(:governed_group) { create(:group, developers: user) }
      let_it_be(:project) { create(:project, :public, :repository, group: governed_group) }
      let_it_be(:merge_request) { create(:merge_request, source_project: project) }

      before do
        stub_feature_flags(duo_mcp_server_governance_rule_enforcement: governed_group)
      end

      def call_tool(name, arguments)
        post api('/mcp', user, oauth_access_token: access_token),
          params: { jsonrpc: '2.0', method: 'tools/call', id: '13', params: { name: name, arguments: arguments } },
          as: :json
      end

      it 'refuses a merge request url with leading text, the way the tool reads it' do
        create(:ai_tool_rule, namespace: governed_group, tool_name: 'get_merge_request', local_access: :deny)

        call_tool('get_merge_request', { url: " #{Gitlab::UrlBuilder.build(merge_request)}" })

        expect_tool_denied('get_merge_request')
      end

      it 'refuses a file url with an encoded space, the way the tool reads it' do
        create(:ai_tool_rule, namespace: governed_group, tool_name: 'get_repository_file', local_access: :deny)

        call_tool('get_repository_file', { url: "#{Gitlab::UrlBuilder.build(project)}/-/blob/master/a%20b.txt" })

        expect_tool_denied('get_repository_file')
      end
    end

    context 'when a tool is denied by tool rules' do
      let_it_be(:governed_group) { create(:group, developers: user) }
      let(:tool_name) { 'get_work_item_types' }

      before do
        stub_feature_flags(duo_mcp_server_governance_rule_enforcement: governed_group)
        create(:ai_tool_rule, namespace: governed_group, tool_name: tool_name, local_access: :deny)
      end

      def call_tool(name, arguments = { group_id: governed_group.id.to_s })
        post api('/mcp', user, oauth_access_token: access_token),
          params: {
            jsonrpc: '2.0', method: 'tools/call', id: '7',
            params: { name: name, arguments: arguments }
          }
      end

      it 'returns a tool execution error with an ok status' do
        call_tool(tool_name)

        expect(response).to have_gitlab_http_status(:ok)
        expect(json_response['error']).to be_nil
        text = "#{tool_name} is denied by an Always Deny rule in #{governed_group.full_path}."
        expect(json_response['result']).to eq(
          'content' => [{ 'type' => 'text', 'text' => text }], 'structuredContent' => {}, 'isError' => true
        )
      end

      it 'rejects a call that names the group by url' do
        call_tool(tool_name, { url: "#{Gitlab.config.gitlab.url}/groups/#{governed_group.full_path}" })

        expect_tool_denied(tool_name)
      end

      it 'echoes the request id' do
        call_tool(tool_name)

        expect(json_response['id']).to eq('7')
      end

      context 'when the caller cannot read the governed group' do
        let_it_be(:hidden_group) { create(:group, :private) }

        before do
          stub_feature_flags(duo_mcp_server_governance_rule_enforcement: hidden_group)
        end

        it 'lets the tool answer rather than refusing the call' do
          create(:ai_tool_rule, namespace: hidden_group, tool_name: tool_name, local_access: :deny)
          call_tool(tool_name, { group_id: hidden_group.id.to_s })

          expect(response).to have_gitlab_http_status(:ok)
          expect(json_response['error']).to be_nil
          expect(json_response.dig('result', 'isError')).to be(true)
          expect(json_response.dig('result', 'content', 0, 'text')).not_to start_with("#{tool_name} is denied")
        end

        it 'does not reveal whether the group has a deny rule' do
          call_tool(tool_name, { group_id: hidden_group.id.to_s })
          without_rule = [response.status, json_response]

          create(:ai_tool_rule, namespace: hidden_group, tool_name: tool_name, local_access: :deny)
          call_tool(tool_name, { group_id: hidden_group.id.to_s })

          expect([response.status, json_response]).to eq(without_rule)
        end
      end

      context 'when the tool is unlisted' do
        let_it_be(:project) { create(:project, group: governed_group) }
        let(:tool_name) { 'get_issue' }

        it 'is absent from tools/list yet still refused when called' do
          post api('/mcp', user, oauth_access_token: access_token),
            params: { jsonrpc: '2.0', method: 'tools/list', id: '8' }

          expect(json_response.dig('result', 'tools').pluck('name')).not_to include(tool_name)

          call_tool(tool_name, { id: project.full_path, issue_iid: '1' })

          expect_tool_denied(tool_name)
        end
      end

      context 'when the local column denies the tool and the web column allows it' do
        let_it_be(:chat_project) { create(:project, group: governed_group) }
        let_it_be(:auth_response) do
          Ai::UserAuthorizable::Response.new(allowed?: true, namespace_ids: [governed_group.id])
        end

        let(:workflow) do
          create(:duo_workflows_workflow, :agentic_chat, project: chat_project, user: user, environment: :web)
        end

        before do
          ::Ai::ToolRule.find_by!(namespace: governed_group, tool_name: tool_name).update!(web_access: :allow)
          allow(::Gitlab::Llm::StageCheck).to receive(:available?).and_return(true)
          allow_any_instance_of(User).to receive(:allowed_to_use).and_return(auth_response) # rubocop:disable RSpec/AnyInstanceOf -- the API loads its own copy of the user
          chat_project.project_setting.update!(duo_features_enabled: true)
        end

        def call_tool_with(token, headers: {})
          post api('/mcp', user, oauth_access_token: token),
            params: { jsonrpc: '2.0', method: 'tools/call', id: '7',
                      params: { name: tool_name, arguments: { group_id: governed_group.id.to_s } } },
            headers: headers
        end

        it 'reads the web column for a token bound to a web chat' do
          call_tool_with(create(:oauth_access_token, user: user, scopes: [:mcp, "duo_workflow:#{workflow.id}"]))

          expect(response).to have_gitlab_http_status(:ok)
          expect(json_response['error']).to be_nil
          expect(json_response.dig('result', 'isError')).to be(false)
        end

        it 'keeps the local column when only the workflow header names the chat' do
          call_tool_with(access_token, headers: { 'X-Gitlab-Duo-Workflow-Id' => workflow.id.to_s })

          expect_tool_denied(tool_name)
        end

        context 'when every column allows the tool' do
          before do
            ::Ai::ToolRule.find_by!(namespace: governed_group, tool_name: tool_name).update!(local_access: :allow)
          end

          it 'runs it for a token with no workflow' do
            call_tool_with(access_token)

            expect(response).to have_gitlab_http_status(:ok)
            expect(json_response.dig('result', 'isError')).to be(false)
          end

          it 'refuses a token bound to a workflow that no longer exists' do
            call_tool_with(create(:oauth_access_token, user: user,
              scopes: [:mcp, "duo_workflow:#{non_existing_record_id}"]))

            expect_session_refused(tool_name)
          end

          it 'refuses a token bound to a workflow the caller cannot read' do
            other_workflow = create(:duo_workflows_workflow, :agentic_chat, project: create(:project, :private),
              environment: :web)

            call_tool_with(create(:oauth_access_token, user: user, scopes: [:mcp, "duo_workflow:#{other_workflow.id}"]))

            expect_session_refused(tool_name)
          end
        end

        context "when a background Developer Flow calls through its service account's composite token" do
          let_it_be(:service_account) do
            create(:user, :service_account, composite_identity_enforced: true, developer_of: governed_group)
          end

          let(:rule) { ::Ai::ToolRule.find_by!(namespace: governed_group, tool_name: tool_name) }
          let(:workflow) do
            create(:duo_workflows_workflow, project: chat_project, user: user, workflow_definition: 'developer/v1',
              environment: :ambient)
          end

          let(:service_account_token) do
            create(:oauth_access_token, user: service_account,
              scopes: [:ai_workflows, :mcp, "user:#{user.id}", "duo_workflow:#{workflow.id}"])
          end

          it 'runs the tool when only the background column allows it' do
            rule.update!(web_access: :deny, background_access: :allow)

            call_tool_with(service_account_token)

            expect(response).to have_gitlab_http_status(:ok)
            expect(json_response['error']).to be_nil
            expect(json_response.dig('result', 'isError')).to be(false)
          end

          it 'refuses the tool when only the background column denies it' do
            rule.update!(local_access: :allow, web_access: :allow, background_access: :deny)

            call_tool_with(service_account_token)

            expect(json_response.dig('result', 'content', 0, 'text'))
              .to eq("#{tool_name} is denied by an Always Deny rule in #{governed_group.full_path}.")
          end
        end
      end

      context 'when the flag is disabled' do
        before do
          stub_feature_flags(duo_mcp_server_governance_rule_enforcement: false)
        end

        it 'executes the tool instead of rejecting it' do
          call_tool(tool_name)

          expect(response).to have_gitlab_http_status(:ok)
          expect(json_response['error']).to be_nil
          expect(json_response.dig('result', 'isError')).to be(false)
        end
      end
    end
  end
end
