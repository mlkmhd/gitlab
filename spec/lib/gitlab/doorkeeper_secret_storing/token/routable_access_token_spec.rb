# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Gitlab::DoorkeeperSecretStoring::Token::RoutableAccessToken, feature_category: :system_access do
  let_it_be(:user) { create(:user) }
  let_it_be(:other_user) { create(:user) }
  let_it_be(:organization) { create(:organization) }

  def routing_payload(token)
    Authn::TokenField::Decoders::V1::RoutablePayload.new(token).decode
  end

  describe '.generate' do
    let(:attributes) { { resource_owner_id: user.id, organization_id: organization.id, scopes: 'api' } }

    subject(:token) { described_class.generate(attributes) }

    before do
      stub_config_cell({ enabled: true, id: 42 })
    end

    it 'generates a routable token with the cell, organization and user', :aggregate_failures do
      expect(described_class.token?(token)).to be(true)
      expect(routing_payload(token)).to eq('c' => 42, 'o' => organization.id, 'u' => user.id)
    end

    it 'generates a different token each time' do
      expect(token).not_to eq(described_class.generate(attributes))
    end

    context 'without a resource owner' do
      let(:attributes) { { resource_owner_id: nil, organization_id: organization.id, scopes: 'api' } }

      it 'generates a routable token with the cell and organization only' do
        expect(routing_payload(token)).to eq('c' => 42, 'o' => organization.id)
      end
    end

    context 'when the routable_oauth_access_token feature flag is disabled' do
      before do
        stub_feature_flags(routable_oauth_access_token: false)
      end

      it 'generates a 64 character hex token' do
        expect(token).to match(/\A\h{64}\z/)
      end
    end

    context 'when the routable_oauth_access_token feature flag is enabled for another user' do
      before do
        stub_feature_flags(routable_oauth_access_token: other_user)
      end

      it 'generates a 64 character hex token' do
        expect(token).to match(/\A\h{64}\z/)
      end

      context 'without a resource owner' do
        let(:attributes) { { resource_owner_id: nil, organization_id: organization.id, scopes: 'api' } }

        it 'generates a 64 character hex token' do
          expect(token).to match(/\A\h{64}\z/)
        end
      end
    end
  end

  describe '.token?' do
    let(:routable_token) do
      Authn::TokenField::Generator::RoutableToken
        .new(nil, routing_payload: { o: ->(_) { 1 } }, prefix: prefix)
        .generate_token
    end

    context 'with a routable token without a prefix' do
      let(:prefix) { '' }

      it { expect(described_class.token?(routable_token)).to be(true) }

      it 'does not match when the payload length does not match the token' do
        expect(described_class.token?("a#{routable_token}")).to be(false)
      end
    end

    context 'with a routable personal access token' do
      include_context 'with token authenticatable routable token context'

      it 'does not match' do
        expect(described_class.token?(create(:personal_access_token).token)).to be(false)
      end

      context 'when the PAT prefix is blank' do
        before do
          stub_application_setting(personal_access_token_prefix: '')
        end

        it 'matches, because the formats are the same' do
          expect(described_class.token?(create(:personal_access_token).token)).to be(true)
        end
      end
    end

    it 'does not match other values', :aggregate_failures do
      expect(described_class.token?(SecureRandom.hex(32))).to be(false)
      expect(described_class.token?('')).to be(false)
      expect(described_class.token?(nil)).to be(false)
    end
  end
end
