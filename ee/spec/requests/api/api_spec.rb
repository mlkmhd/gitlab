# frozen_string_literal: true

require 'spec_helper'

RSpec.describe API::API, feature_category: :system_access do
  include Auth::DpopTokenHelper

  describe 'logging', :aggregate_failures do
    let_it_be(:project) { create(:project, :public) }
    let_it_be(:user) { project.first_owner }

    context 'when the method is not allowed' do
      it 'logs the route and context metadata for the client' do
        expect(described_class::LOG_FORMATTER).to receive(:call) do |_severity, _datetime, _, data|
          expect(data.stringify_keys)
            .to include('correlation_id' => an_instance_of(String),
              'meta.remote_ip' => an_instance_of(String),
              'meta.client_id' => a_string_matching(%r{\Aip/.+}),
              'route' => '/api/scim/:version/groups/:group/Users/:id')

          expect(data.stringify_keys).not_to include('meta.caller_id', 'meta.user')
        end

        allow(Gitlab::Auth::GroupSaml::Config).to receive(:enabled?).and_return(true)

        process(:put, '/api/scim/v2/groups/1/Users/foo')

        expect(response).to have_gitlab_http_status(:method_not_allowed)
      end
    end
  end

  describe 'DPoP authentication' do
    shared_examples "checks for dpop token" do
      let(:dpop_proof) { generate_dpop_proof_for(user) }

      context 'with a missing DPoP token' do
        it 'returns 401' do
          get api(request_path, personal_access_token: personal_access_token)

          expect(json_response["error_description"]).to eq("DPoP validation error: DPoP header is missing")
          expect(response).to have_gitlab_http_status(:unauthorized)
        end
      end

      context 'with a valid DPoP token' do
        it 'returns 200' do
          get(api(request_path, personal_access_token: personal_access_token), headers: { "dpop" => dpop_proof.proof })
          expect(response).to have_gitlab_http_status(:ok)
        end
      end

      context 'with a malformed DPoP token' do
        it 'returns 401' do
          get(api(request_path, personal_access_token: personal_access_token), headers: { "dpop" => 'invalid' })
          # rubocop:disable Layout/LineLength -- We need the entire error message
          expect(json_response["error_description"]).to eq("DPoP validation error: Malformed JWT, unable to decode. Not enough or too many segments")
          # rubocop:enable Layout/LineLength
          expect(response).to have_gitlab_http_status(:unauthorized)
        end
      end
    end

    shared_examples "valid manage endpoint request", :saas do
      it 'returns :success' do
        get api(request_path, personal_access_token: personal_access_token)

        expect(response).to have_gitlab_http_status(:ok)
      end
    end

    shared_examples "invalid `/manage` endpoint request", :saas do
      it 'returns 404 not found' do
        get api(request_path, personal_access_token: personal_access_token)

        expect(response).to have_gitlab_http_status(:not_found)
      end
    end

    context 'when :dpop_authentication FF is disabled' do
      let(:user) { create(:user) }
      let(:personal_access_token) { create(:personal_access_token, user: user, scopes: [:api]) }
      let(:group) { create(:group) }
      let(:request_path) { "/groups/#{group.id}/manage/personal_access_tokens" }

      before do
        group.add_owner(user)

        stub_feature_flags(dpop_authentication: false)
      end

      context "when its a request to a `/manage` endpoint" do
        context "when the Group-level DPoP setting is disabled (default)" do
          before do
            group.update!(require_dpop_for_manage_api_endpoints: false)
          end

          it_behaves_like "valid manage endpoint request"
        end

        context "when the Group-level DPoP setting is enabled" do
          before do
            group.update!(require_dpop_for_manage_api_endpoints: true)
          end

          it_behaves_like "valid manage endpoint request"
        end
      end
    end

    context 'when :dpop_authentication FF is enabled', :saas do
      let(:user) { create(:user) }
      let(:personal_access_token) { create(:personal_access_token, user: user, scopes: [:api]) }
      let(:group) { create(:group) }
      let(:request_path) { "/groups/#{group.id}/manage/personal_access_tokens" }

      before do
        group.add_owner(user)

        stub_feature_flags(dpop_authentication: true)
      end

      context 'when user-level DPoP is disabled' do
        context "when its a request to a `/manage` endpoint" do
          context "when the Group-level DPoP setting is disabled (default)" do
            before do
              group.update!(require_dpop_for_manage_api_endpoints: false)
            end

            it_behaves_like "valid manage endpoint request"
          end

          context "when the Group-level DPoP setting is enabled" do
            before do
              group.update!(require_dpop_for_manage_api_endpoints: true)
            end

            it_behaves_like "checks for dpop token"
          end
        end
      end

      context 'when user-level DPoP is enabled' do
        let(:user) { create(:user, dpop_enabled: true) }
        let(:oauth_token) { create(:oauth_access_token, user: user, scopes: [:api]) }

        context 'when API is called with an OAuth token' do
          it 'does not invoke DPoP' do
            get api('/groups', oauth_access_token: oauth_token)
            expect(response).to have_gitlab_http_status(:ok)
          end
        end

        it_behaves_like "checks for dpop token"
      end
    end
  end

  describe 'Language Server client restrictions on Dedicated', :dedicated, feature_category: :editor_extensions do
    let_it_be(:user) { create(:user) }
    let_it_be(:oauth_access_token) { create(:oauth_access_token, user: user, scopes: [:api]) }
    let_it_be(:personal_access_token) { create(:personal_access_token, user: user, scopes: [:api]) }
    let(:request_path) { '/version' }

    shared_examples 'an allowed client' do
      it 'returns 200 when using an OAuth token' do
        get(api(request_path, oauth_access_token: oauth_access_token), headers: headers)

        expect(response).to have_gitlab_http_status(:ok)
      end

      it 'returns 200 when using a Personal Access Token' do
        get(api(request_path, personal_access_token: personal_access_token), headers: headers)

        expect(response).to have_gitlab_http_status(:ok)
      end
    end

    shared_examples 'an unallowed client' do
      it 'returns 401 when using an OAuth token' do
        get(api(request_path, oauth_access_token: oauth_access_token), headers: headers)

        expect(json_response['error_description']).to a_string_including(
          'Requests from Editor Extension clients are restricted')
        expect(response).to have_gitlab_http_status(:unauthorized)
      end

      it 'returns 401 when using a Personal Access Token' do
        get(api(request_path, personal_access_token: personal_access_token), headers: headers)

        expect(json_response['error_description']).to a_string_including(
          'Requests from Editor Extension clients are restricted')
        expect(response).to have_gitlab_http_status(:unauthorized)
      end
    end

    before do
      stub_feature_flags(enforce_language_server_version: false)

      allow(Gitlab::CurrentSettings.current_application_settings).to receive_messages(
        enable_language_server_restrictions: true,
        minimum_language_server_version: '1.0.0')
    end

    context 'with allowed clients' do
      using RSpec::Parameterized::TableSyntax

      where(:client_version, :user_agent) do
        '1.0.0' | 'gitlab-language-server 1.0.0'
        '2.0.0' | 'gitlab-language-server 2.0.0'
      end

      with_them do
        let(:headers) do
          {
            'User-Agent' => user_agent,
            'X-GitLab-Language-Server-Version' => client_version
          }
        end

        it_behaves_like 'an allowed client'
      end
    end

    context 'with unallowed clients' do
      using RSpec::Parameterized::TableSyntax

      where(:client_version, :user_agent) do
        '0.1.0' | 'code-completions-language-server-experiment (gl-visual-studio-extension:1.0.0.0; arch:X64;)'
        '0.1.0' | 'gitlab-language-server 1.0.0'
        '0.1.0' | nil
        nil     | 'code-completions-language-server-experiment (gl-visual-studio-extension:1.0.0.0; arch:X64;)'
        nil     | 'gitlab-language-server 0.1.0'
      end

      with_them do
        let(:headers) do
          {
            'User-Agent' => user_agent,
            'X-GitLab-Language-Server-Version' => client_version
          }
        end

        it_behaves_like 'an unallowed client'
      end
    end
  end
end
