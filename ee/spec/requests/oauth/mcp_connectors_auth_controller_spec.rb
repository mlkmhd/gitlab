# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Oauth::McpConnectorsAuthController, :clean_gitlab_redis_sessions, :with_current_organization, feature_category: :ai_catalog_curation do
  include SessionHelpers

  let_it_be(:user, freeze: false) { create(:user) }
  let_it_be(:mcp_server) { create(:ai_catalog_mcp_server, :with_oauth, organization: current_organization) }

  before do
    sign_in(user)
  end

  shared_examples 'returns 404' do
    it 'returns 404' do
      subject

      expect(response).to have_gitlab_http_status(:not_found)
    end
  end

  shared_examples 'redirects to sign-in' do
    it 'redirects to the sign-in page' do
      subject

      expect(response).to redirect_to(new_user_session_path)
    end
  end

  describe 'GET /oauth/mcp_connectors/connect' do
    subject(:connect) { get oauth_mcp_connectors_connect_path, params: { id: mcp_server.id } }

    let(:authorization_url) { 'https://auth.example.com/oauth/authorize?client_id=x&state=y' }

    context 'when the user is not authenticated' do
      before do
        sign_out(user)
      end

      it_behaves_like 'redirects to sign-in'
    end

    context 'when the user is not authorized' do
      before do
        allow(Ability).to receive(:allowed?).and_call_original
        allow(Ability).to receive(:allowed?)
          .with(user, :read_ai_catalog_mcp_server, mcp_server)
          .and_return(false)
      end

      it_behaves_like 'returns 404'
    end

    context 'when the user is authorized' do
      before do
        allow(Ability).to receive(:allowed?).and_call_original
        allow(Ability).to receive(:allowed?)
          .with(user, :read_ai_catalog_mcp_server, mcp_server)
          .and_return(true)
      end

      context 'when an OAuth2::Error is raised' do
        before do
          allow_next_instance_of(Ai::Catalog::McpServers::ConnectService) do |instance|
            allow(instance).to receive(:execute).and_raise(OAuth2::Error, 'oauth error')
          end
        end

        it 'redirects to root with an alert' do
          connect

          expect(response).to redirect_to(root_path)
          expect(flash[:alert]).to eq('OAuth error occurred. Please try again.')
        end
      end

      context 'when the service succeeds' do
        let(:code_verifier) { 'test-pkce-verifier' }

        before do
          allow_next_instance_of(Ai::Catalog::McpServers::ConnectService) do |instance|
            allow(instance).to receive(:execute).and_return(
              ServiceResponse.success(
                payload: { authorization_url: authorization_url, code_verifier: code_verifier }
              )
            )
          end
        end

        it 'redirects to the authorization URL' do
          connect

          expect(response).to redirect_to(authorization_url)
        end

        it 'stores the code_verifier in the session namespaced by server ID' do
          connect

          expect(session[:"mcp_oauth_code_verifier_#{mcp_server.id}"]).to eq(code_verifier)
        end

        context 'when connecting to multiple servers concurrently' do
          let_it_be(:another_mcp_server) do
            create(:ai_catalog_mcp_server, :with_oauth, organization: current_organization)
          end

          let(:another_code_verifier) { 'another-test-pkce-verifier' }
          let(:another_authorization_url) { 'https://auth.example.com/oauth/authorize?client_id=y&state=z' }

          before do
            allow(Ability).to receive(:allowed?)
              .with(user, :read_ai_catalog_mcp_server, another_mcp_server)
              .and_return(true)

            allow_next_instance_of(Ai::Catalog::McpServers::ConnectService) do |instance|
              allow(instance).to receive(:execute).and_return(
                ServiceResponse.success(
                  payload: { authorization_url: authorization_url, code_verifier: code_verifier }
                )
              )
            end
          end

          it 'stores code_verifiers for different servers without collision' do
            # Connect to first server
            get oauth_mcp_connectors_connect_path, params: { id: mcp_server.id }
            expect(session[:"mcp_oauth_code_verifier_#{mcp_server.id}"]).to eq(code_verifier)

            # Connect to second server
            allow_next_instance_of(Ai::Catalog::McpServers::ConnectService) do |instance|
              allow(instance).to receive(:execute).and_return(
                ServiceResponse.success(
                  payload: { authorization_url: another_authorization_url, code_verifier: another_code_verifier }
                )
              )
            end

            get oauth_mcp_connectors_connect_path, params: { id: another_mcp_server.id }

            # Both verifiers should be stored independently
            expect(session[:"mcp_oauth_code_verifier_#{mcp_server.id}"]).to eq(code_verifier)
            expect(session[:"mcp_oauth_code_verifier_#{another_mcp_server.id}"]).to eq(another_code_verifier)
          end
        end
      end

      context 'when the service fails' do
        before do
          allow_next_instance_of(Ai::Catalog::McpServers::ConnectService) do |instance|
            allow(instance).to receive(:execute).and_return(
              ServiceResponse.error(message: 'This MCP server does not use OAuth authentication')
            )
          end
        end

        it 'redirects back with an alert' do
          connect

          expect(response).to redirect_to(root_path)
          expect(flash[:alert]).to eq('This MCP server does not use OAuth authentication')
        end

        context 'when return_to is given' do
          subject(:connect) do
            get oauth_mcp_connectors_connect_path, params: { id: mcp_server.id, return_to: 'https://evil.example.com/-/user_settings/integration_accounts' }
          end

          it 'redirects to the return_to path on GitLab with an alert' do
            connect

            expect(response).to redirect_to('/-/user_settings/integration_accounts')
            expect(flash[:alert]).to eq('This MCP server does not use OAuth authentication')
          end
        end
      end
    end
  end

  describe 'POST /oauth/mcp_connectors/disconnect' do
    subject(:disconnect) { post oauth_mcp_connectors_disconnect_path, params: { id: mcp_server.id } }

    context 'when the user is not authenticated' do
      before do
        sign_out(user)
      end

      it_behaves_like 'redirects to sign-in'
    end

    context 'when the user is not authorized' do
      before do
        allow(Ability).to receive(:allowed?).and_call_original
        allow(Ability).to receive(:allowed?)
          .with(user, :read_ai_catalog_mcp_server, mcp_server)
          .and_return(false)
      end

      it_behaves_like 'returns 404'
    end

    context 'when the user is authorized' do
      before do
        allow(Ability).to receive(:allowed?).and_call_original
        allow(Ability).to receive(:allowed?)
          .with(user, :read_ai_catalog_mcp_server, mcp_server)
          .and_return(true)
      end

      context 'when the service succeeds' do
        before do
          allow_next_instance_of(Ai::Catalog::McpServers::RevokeTokenService) do |instance|
            allow(instance).to receive(:execute).and_return(ServiceResponse.success)
          end
        end

        it 'returns 200 OK' do
          disconnect

          expect(response).to have_gitlab_http_status(:ok)
        end

        it 'returns an empty JSON body' do
          disconnect

          expect(response.parsed_body).to eq({})
        end
      end

      context 'when the service fails' do
        before do
          allow_next_instance_of(Ai::Catalog::McpServers::RevokeTokenService) do |instance|
            allow(instance).to receive(:execute).and_return(
              ServiceResponse.error(message: 'No connection found for this MCP server')
            )
          end
        end

        it 'returns 422 unprocessable entity' do
          disconnect

          expect(response).to have_gitlab_http_status(:unprocessable_entity)
        end

        it 'returns the error message in the JSON body' do
          disconnect

          expect(response.parsed_body).to eq({ 'message' => 'No connection found for this MCP server' })
        end
      end
    end
  end

  describe 'GET /oauth/mcp_connectors/callback' do
    let(:return_to) { '/dashboard' }
    let(:valid_state) do
      ::Gitlab::Oauth::ClientState.new(
        return_to: return_to,
        data: { mcp_server_id: mcp_server.id }
      ).encode
    end

    subject(:callback) { get oauth_mcp_connectors_callback_path, params: { state: valid_state, code: 'auth-code' } }

    context 'when the user is not authenticated' do
      before do
        sign_out(user)
      end

      it_behaves_like 'redirects to sign-in'
    end

    context 'when the user is not authorized' do
      before do
        allow(Ability).to receive(:allowed?).and_call_original
        allow(Ability).to receive(:allowed?)
          .with(user, :read_ai_catalog_mcp_server, mcp_server)
          .and_return(false)
      end

      it_behaves_like 'returns 404'
    end

    context 'when the user is authorized' do
      before do
        allow(Ability).to receive(:allowed?).and_call_original
        allow(Ability).to receive(:allowed?)
          .with(user, :read_ai_catalog_mcp_server, mcp_server)
          .and_return(true)
      end

      context 'when the state is invalid' do
        subject(:callback) { get oauth_mcp_connectors_callback_path, params: { state: 'invalid-state', code: 'code' } }

        it 'redirects to root with an alert' do
          callback

          expect(response).to redirect_to(root_path)
          expect(flash[:alert]).to eq('OAuth state mismatch. Please try again.')
        end
      end

      context 'when the state is valid' do
        let(:code_verifier) { 'test-pkce-verifier' }

        before do
          stub_session(session_data: { "mcp_oauth_code_verifier_#{mcp_server.id}" => code_verifier })
        end

        context 'when the service succeeds' do
          before do
            allow_next_instance_of(Ai::Catalog::McpServers::CallbackService) do |instance|
              allow(instance).to receive(:execute).and_return(ServiceResponse.success)
            end
          end

          it 'redirects to return_to with a notice' do
            callback

            expect(response).to redirect_to(return_to)
            expect(flash[:notice]).to eq('Successfully connected to MCP server')
          end

          it 'passes the code_verifier from the session to CallbackService' do
            service = instance_double(Ai::Catalog::McpServers::CallbackService, execute: ServiceResponse.success)
            expect(Ai::Catalog::McpServers::CallbackService).to receive(:new).with(
              hash_including(code_verifier: code_verifier)
            ).and_return(service)

            callback
          end
        end

        context 'when the user cancels on the MCP server' do
          subject(:callback) do
            get oauth_mcp_connectors_callback_path, params: { state: valid_state, error: 'access_denied' }
          end

          it 'redirects to return_to with an alert, without exchanging a code', :aggregate_failures do
            expect(Ai::Catalog::McpServers::CallbackService).not_to receive(:new)

            callback

            expect(response).to redirect_to(return_to)
            expect(flash[:alert]).to eq('MCP server access was not granted: access_denied')
          end

          it 'clears the code_verifier from the session' do
            callback

            expect(session[:"mcp_oauth_code_verifier_#{mcp_server.id}"]).to be_nil
          end

          context 'when the state has no return_to' do
            let(:valid_state) do
              ::Gitlab::Oauth::ClientState.new(return_to: '', data: { mcp_server_id: mcp_server.id })
                .encode.delete_suffix(':')
            end

            it 'redirects to root with an alert' do
              callback

              expect(response).to redirect_to(root_path)
              expect(flash[:alert]).to eq('MCP server access was not granted: access_denied')
            end
          end

          context 'when the error is not a standard OAuth error code' do
            subject(:callback) do
              get oauth_mcp_connectors_callback_path,
                params: { state: valid_state, error: 'Your session expired, sign in at evil.example.com' }
            end

            it 'shows a generic alert without the error text' do
              callback

              expect(flash[:alert]).to eq('MCP server access was not granted.')
            end
          end
        end

        context 'when the service fails' do
          before do
            allow_next_instance_of(Ai::Catalog::McpServers::CallbackService) do |instance|
              allow(instance).to receive(:execute).and_return(
                ServiceResponse.error(message: 'Failed to connect to MCP server: connection refused')
              )
            end
          end

          it 'redirects to return_to with an alert' do
            callback

            expect(response).to redirect_to(return_to)
            expect(flash[:alert]).to eq('Failed to connect to MCP server: connection refused')
          end
        end
      end
    end
  end

  # No ability stubs: these go through McpServerPolicy.
  describe 'authorization on the server' do
    let_it_be(:slack_server) do
      create(:ai_catalog_mcp_server, :with_oauth, organization: current_organization,
        url: Ai::Catalog::McpServers::SlackHelper::MCP_URL, oauth_client_id: 'gitlab-slack-app-id')
    end

    let_it_be(:other_organization_server) do
      create(:ai_catalog_mcp_server, :with_oauth, organization: create(:organization))
    end

    let(:mcp_servers_available) { false }
    let(:state) { ::Gitlab::Oauth::ClientState.new(return_to: '/dashboard', data: { mcp_server_id: server.id }).encode }

    before do
      current_organization.users << user unless current_organization.user?(user)
      stub_application_setting(slack_app_id: 'gitlab-slack-app-id')
      allow(::Ai::Catalog).to receive(:mcp_servers_available?).and_return(mcp_servers_available)
      allow_next_instance_of(Ai::Catalog::McpServers::ConnectService) do |instance|
        allow(instance).to receive(:execute).and_return(
          ServiceResponse.success(payload: { authorization_url: 'https://slack.com/oauth', code_verifier: 'v' })
        )
      end
      allow_next_instance_of(Ai::Catalog::McpServers::CallbackService) do |instance|
        allow(instance).to receive(:execute).and_return(ServiceResponse.success)
      end
      allow_next_instance_of(Ai::Catalog::McpServers::RevokeTokenService) do |instance|
        allow(instance).to receive(:execute).and_return(ServiceResponse.success)
      end
    end

    context 'with the GitLab for Slack app server, when AI Catalog MCP servers are not available' do
      let(:server) { slack_server }

      it 'starts the connection' do
        get oauth_mcp_connectors_connect_path, params: { id: server.id }

        expect(response).to redirect_to('https://slack.com/oauth')
      end

      it 'completes the connection' do
        get oauth_mcp_connectors_callback_path, params: { state: state, code: 'auth-code' }

        expect(response).to redirect_to('/dashboard')
        expect(flash[:notice]).to eq('Successfully connected to MCP server')
      end

      it 'disconnects' do
        post oauth_mcp_connectors_disconnect_path, params: { id: server.id }

        expect(response).to have_gitlab_http_status(:ok)
      end
    end

    context 'with another server, when AI Catalog MCP servers are not available' do
      let(:server) { mcp_server }

      it 'does not connect' do
        get oauth_mcp_connectors_connect_path, params: { id: server.id }

        expect(response).to have_gitlab_http_status(:not_found)
      end

      it 'does not complete the connection' do
        get oauth_mcp_connectors_callback_path, params: { state: state, code: 'auth-code' }

        expect(response).to have_gitlab_http_status(:not_found)
      end

      it 'does not disconnect' do
        post oauth_mcp_connectors_disconnect_path, params: { id: server.id }

        expect(response).to have_gitlab_http_status(:not_found)
      end

      context 'when the user is connected to it' do
        before do
          create(:ai_catalog_mcp_servers_user, mcp_server: server, user: user, organization: current_organization)
        end

        it 'still lets the user revoke their own connection' do
          post oauth_mcp_connectors_disconnect_path, params: { id: server.id }

          expect(response).to have_gitlab_http_status(:ok)
        end
      end
    end

    context 'with a server in another organization, when AI Catalog MCP servers are available' do
      let(:mcp_servers_available) { true }
      let(:server) { other_organization_server }

      it 'does not connect' do
        get oauth_mcp_connectors_connect_path, params: { id: server.id }

        expect(response).to have_gitlab_http_status(:not_found)
      end

      it 'does not complete the connection' do
        get oauth_mcp_connectors_callback_path, params: { state: state, code: 'auth-code' }

        expect(response).to have_gitlab_http_status(:not_found)
      end
    end
  end
end
