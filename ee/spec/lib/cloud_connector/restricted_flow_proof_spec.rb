# frozen_string_literal: true

require 'spec_helper'

RSpec.describe CloudConnector::RestrictedFlowProof, feature_category: :duo_agent_platform do
  subject(:token) { described_class.new(flow_config_id: 'bl_security', workflow_id: 42).token }

  context 'with a signing key' do
    let_it_be(:cloud_connector_key) { create(:cloud_connector_keys) }

    before do
      allow(::CloudConnector::CachingKeyLoader).to receive(:private_jwk).and_return(cloud_connector_key.to_jwk)
    end

    it 'is an RS256 JWT signed with the instance key', :aggregate_failures do
      claims, header = cloud_connector_key.decode_token(token)

      expect(claims).to be_a(Hash)
      expect(header).to include('alg' => 'RS256', 'typ' => 'JWT', 'kid' => cloud_connector_key.to_jwk.kid)
    end

    it 'carries only the proof claims', :freeze_time do
      claims, _header = cloud_connector_key.decode_token(token)

      expect(claims).to be_a(Hash)
      expect(claims.except('jti')).to eq(
        'iss' => Doorkeeper::OpenidConnect.configuration.issuer,
        'sub' => Gitlab::CurrentSettings.uuid,
        'aud' => ['gitlab-duo-workflow-service'],
        'typ' => 'restricted_flow_proof',
        'flow_config_id' => 'bl_security',
        'workflow_id' => '42',
        'iat' => Time.current.to_i,
        'nbf' => Time.current.to_i - 5,
        'exp' => Time.current.to_i + 3600
      )
    end

    it 'has a unique jti per token' do
      other = described_class.new(flow_config_id: 'bl_security', workflow_id: 42).token

      expect(JWT.decode(token, nil, false).first['jti']).not_to eq(JWT.decode(other, nil, false).first['jti'])
    end
  end

  context 'when signing fails' do
    using RSpec::Parameterized::TableSyntax

    let_it_be(:cloud_connector_key) { create(:cloud_connector_keys) }

    where(:error) do
      [ActiveRecord::Encryption::Errors::Decryption, OpenSSL::PKey::RSAError, JWT::JWKError, JWT::EncodeError]
    end

    with_them do
      before do
        allow(::CloudConnector::CachingKeyLoader).to receive(:private_jwk).and_raise(error)
      end

      it 'returns nil and tracks the error' do
        expect(::Gitlab::ErrorTracking).to receive(:track_exception).with(
          an_instance_of(error),
          message: 'Cloud Connector: could not sign the restricted-flow proof',
          flow_config_id: 'bl_security'
        )

        expect(token).to be_nil
      end
    end
  end

  context 'without a signing key' do
    it 'returns nil and logs at info' do
      allow(::Gitlab::AppLogger).to receive(:info)
      expect(::Gitlab::AppLogger).to receive(:info).with(
        message: 'Cloud Connector: no signing key, so no restricted-flow proof is sent',
        flow_config_id: 'bl_security'
      )

      expect(token).to be_nil
    end
  end
end
