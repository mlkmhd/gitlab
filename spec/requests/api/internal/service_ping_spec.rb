# frozen_string_literal: true

require 'spec_helper'

RSpec.describe API::Internal::ServicePing, feature_category: :service_ping do
  include_context 'workhorse headers'

  let(:secret) { SecureRandom.random_bytes(Gitlab::JwtAuthenticatable::SECRET_LENGTH) }

  let(:claims) do
    {
      'iss' => ServicePing::InternalApiAuthenticator::JWT_ISSUER,
      'aud' => ServicePing::InternalApiAuthenticator::JWT_AUDIENCE,
      'sub' => 'service-ping-exporter',
      'iat' => Time.current.to_i
    }
  end

  let(:service_ping_header) do
    { ServicePing::InternalApiAuthenticator::API_HEADER => JWT.encode(claims, secret, 'HS256') }
  end

  before do
    allow(ServicePing::InternalApiAuthenticator).to receive(:secret).and_return(secret)
  end

  describe 'GET /internal/service_ping/instance' do
    def send_request(headers: service_ping_header.merge(workhorse_headers))
      get api('/internal/service_ping/instance'), headers: headers
    end

    it 'returns the instance identity' do
      send_request

      expect(response).to have_gitlab_http_status(:ok)
      expect(json_response['identity']).to eq(ServicePing::InstanceIdentity.to_h.stringify_keys)
    end

    describe 'Service Ping settings' do
      using RSpec::Parameterized::TableSyntax

      # One helper on per row, so a field wired to the wrong helper fails.
      where(:enabled_and_consented, :generation_enabled, :optional_metrics_enabled) do
        true  | false | false
        false | true  | false
        false | false | true
      end

      with_them do
        before do
          allow(::ServicePing::ServicePingSettings)
            .to receive(:enabled_and_consented?).and_return(enabled_and_consented)
          allow(::Gitlab::CurrentSettings).to receive_messages(
            usage_ping_generation_enabled?: generation_enabled,
            usage_ping_features_enabled?: optional_metrics_enabled
          )
        end

        it 'reports each Service Ping helper under its own key' do
          send_request

          expect(json_response['settings']).to eq(
            'service_ping_enabled' => enabled_and_consented,
            'service_ping_generation_enabled' => generation_enabled,
            'service_ping_optional_metrics_enabled' => optional_metrics_enabled
          )
        end
      end
    end

    context 'when the token is missing' do
      it 'returns 401' do
        send_request(headers: workhorse_headers)

        expect(response).to have_gitlab_http_status(:unauthorized)
      end
    end

    context 'when the token is invalid' do
      it 'returns 401' do
        token = JWT.encode(claims.merge('iat' => 6.minutes.ago.to_i), secret, 'HS256')

        send_request(headers: { ServicePing::InternalApiAuthenticator::API_HEADER => token }.merge(workhorse_headers))

        expect(response).to have_gitlab_http_status(:unauthorized)
      end
    end

    context 'when the Workhorse header is missing', :verify_workhorse_jwt do
      it 'returns 403' do
        send_request(headers: service_ping_header)

        expect(response).to have_gitlab_http_status(:forbidden)
      end
    end
  end
end
