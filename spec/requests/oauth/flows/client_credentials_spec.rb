# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'Gitlab OAuth2 Client Credentials Flow', feature_category: :system_access do
  let_it_be(:organization) { create(:organization) }
  let_it_be(:application) { create(:oauth_application, scopes: 'api read_user') }
  let_it_be(:client_id) { application.uid }
  let_it_be(:client_secret) { application.secret }
  let(:token_params) do
    {
      client_id: client_id,
      client_secret: client_secret,
      grant_type: 'client_credentials',
      scope: 'api'
    }
  end

  before do
    allow_next_instance_of(Gitlab::Current::Organization) do |instance|
      allow(instance).to receive(:organization).and_return(organization)
    end
  end

  def fetch_access_token(params = token_params)
    post oauth_token_path, params: params
    json_response
  end

  describe 'client authentication sent by both the Basic header and params' do
    let(:headers) do
      { 'Authorization' => ActionController::HttpAuthentication::Basic.encode_credentials(client_id, client_secret) }
    end

    let(:access_token) { create(:oauth_access_token, application: application, scopes: %w[api]) }
    let(:params) { { client_id: client_id, client_secret: client_secret, token: access_token.plaintext_token } }

    it 'revokes the token' do
      post oauth_revoke_path, params: params, headers: headers

      expect(response).to have_gitlab_http_status(:ok)
      expect(access_token.reload).to be_revoked
    end

    it 'introspects the token' do
      post oauth_introspect_path, params: params, headers: headers

      expect(response).to have_gitlab_http_status(:ok)
      expect(json_response['active']).to be(true)
    end
  end

  describe 'Token Request' do
    context 'when the credentials are sent by both the Basic header and params' do
      let(:basic_credentials) { ActionController::HttpAuthentication::Basic.encode_credentials(client_id, client_secret) }

      it 'returns an access token' do
        post oauth_token_path, params: token_params, headers: { 'Authorization' => basic_credentials }

        expect(response).to have_gitlab_http_status(:ok)
        expect(json_response).to include('access_token', 'token_type', 'expires_in', 'scope')
      end
    end

    context 'with valid client credentials' do
      it 'returns an access token' do
        fetch_access_token

        expect(response).to have_gitlab_http_status(:ok)
        expect(json_response).to include('access_token', 'token_type', 'expires_in', 'scope')
        expect(json_response['expires_in']).to be(Gitlab::CurrentSettings.oauth_access_token_expires_in)
      end

      it 'returns a bearer token type' do
        fetch_access_token

        expect(json_response['token_type']).to eq('Bearer')
      end

      it 'returns a routable access token for the organization, without a user' do
        fetch_access_token

        expect(Authn::TokenField::Decoders::V1::RoutablePayload.new(json_response['access_token']).decode)
          .to include('o' => organization.id).and(exclude('u'))
      end

      it 'does not return a refresh token' do
        fetch_access_token

        expect(json_response).not_to include('refresh_token')
      end

      it 'returns the requested scope' do
        fetch_access_token

        expect(json_response['scope']).to eq('api')
      end
    end

    context 'with invalid client_id' do
      it 'returns an error' do
        fetch_access_token(token_params.merge(client_id: 'invalid'))

        expect(response).to have_gitlab_http_status(:unauthorized)
        expect(json_response['error']).to eq('invalid_client')
      end
    end

    context 'with invalid client_secret' do
      it 'returns an error' do
        fetch_access_token(token_params.merge(client_secret: 'invalid'))

        expect(response).to have_gitlab_http_status(:unauthorized)
        expect(json_response['error']).to eq('invalid_client')
      end
    end

    context 'with missing client_secret' do
      it 'returns an error' do
        fetch_access_token(token_params.except(:client_secret))

        expect(response).to have_gitlab_http_status(:unauthorized)
        expect(json_response['error']).to eq('invalid_client')
      end
    end

    context 'with a scope beyond application limits' do
      it 'returns an invalid_scope error' do
        fetch_access_token(token_params.merge(scope: 'sudo'))

        expect(response).to have_gitlab_http_status(:bad_request)
        expect(json_response['error']).to eq('invalid_scope')
      end
    end

    context 'with no scope specified' do
      it 'returns an access token using the application default scopes' do
        fetch_access_token(token_params.except(:scope))

        expect(response).to have_gitlab_http_status(:ok)
        expect(json_response).to include('access_token')
      end
    end

    context 'with client credentials via HTTP Basic Auth' do
      it 'returns an access token' do
        post oauth_token_path,
          params: { grant_type: 'client_credentials', scope: 'api' },
          headers: { 'Authorization' => ActionController::HttpAuthentication::Basic.encode_credentials(client_id, client_secret) }

        expect(response).to have_gitlab_http_status(:ok)
        expect(json_response).to include('access_token')
      end
    end
  end
end
