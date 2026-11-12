# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Security::SecretDetection::PartnerTokens::TypeformClient, feature_category: :secret_detection do
  using RSpec::Parameterized::TableSyntax

  let(:client) { described_class.new }
  let(:valid_token) { "tfp_aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa" }
  let(:response) { instance_double(Net::HTTPResponse) }
  let(:us_endpoint) { 'https://api.typeform.com/me' }
  let(:eu_endpoint) { 'https://api.typeform.eu/me' }
  let(:auth_failed) { '{"code":"AUTHENTICATION_FAILED","description":"authentication failed"}' }
  let(:insufficient_permissions) do
    '{"code":"INSUFFICIENT_PERMISSIONS","description":"not enough permissions to complete the action"}'
  end

  it_behaves_like 'a partner token client', http_method: :get

  def stub_host(endpoint, code:, body:)
    host_response = instance_double(Net::HTTPResponse, code: code, body: body)
    allow(Integrations::Clients::HTTP).to receive(:get).with(endpoint, anything).and_return(host_response)
  end

  describe '#verify_token' do
    context 'when the vendor reports the token active' do
      before do
        allow(response).to receive_messages(code: '200', body: '{}')
        allow(Integrations::Clients::HTTP).to receive(:get).and_return(response)
      end

      it 'returns active' do
        expect(client.verify_token(valid_token).active?).to be(true)
      end

      it 'does not try the EU host' do
        client.verify_token(valid_token)

        expect(Integrations::Clients::HTTP).to have_received(:get).once
      end
    end

    context 'when the vendor returns 403' do
      where(:body, :status) do
        ref(:insufficient_permissions) | :active
        '{"code":"FORBIDDEN"}'         | :unknown
        '["AUTHENTICATION_FAILED"]'    | :unknown
        'not json'                     | :unknown
        ''                             | :unknown
      end

      with_them do
        before do
          stub_host(us_endpoint, code: '403', body: body)
        end

        it 'returns the mapped status from the US host' do
          expect(client.verify_token(valid_token).status).to eq(status)
          expect(Integrations::Clients::HTTP).to have_received(:get).once
        end
      end
    end

    context 'when the US host does not know the token' do
      before do
        stub_host(us_endpoint, code: '403', body: auth_failed)
      end

      where(:eu_code, :eu_body, :status) do
        '200' | '{}'                           | :active
        '403' | ref(:insufficient_permissions) | :active
        '403' | ref(:auth_failed)              | :inactive
        '403' | '{"code":"FORBIDDEN"}'         | :unknown
        '100' | ''                             | :unknown
      end

      with_them do
        it 'returns the status from the EU host' do
          stub_host(eu_endpoint, code: eu_code, body: eu_body)

          expect(client.verify_token(valid_token).status).to eq(status)
        end
      end

      it 'raises RateLimitError when the EU host rate limits the request' do
        stub_host(eu_endpoint, code: '429', body: '')

        expect { client.verify_token(valid_token) }.to raise_error(described_class::RateLimitError)
      end

      it 'raises NetworkError when the EU host reports a service error' do
        stub_host(eu_endpoint, code: '503', body: '')

        expect { client.verify_token(valid_token) }.to raise_error(described_class::NetworkError)
      end
    end

    context 'when the vendor rate limits the request' do
      before do
        allow(response).to receive_messages(code: '429', body: '')
        allow(Integrations::Clients::HTTP).to receive(:get).and_return(response)
      end

      it 'raises RateLimitError' do
        expect { client.verify_token(valid_token) }.to raise_error(described_class::RateLimitError)
      end
    end

    context 'when the vendor reports a service error' do
      before do
        allow(response).to receive_messages(code: '500', body: '')
        allow(Integrations::Clients::HTTP).to receive(:get).and_return(response)
      end

      it 'raises NetworkError' do
        expect { client.verify_token(valid_token) }.to raise_error(described_class::NetworkError)
      end
    end

    it 'sends the bearer token' do
      expected_header = { "Authorization" => "Bearer #{valid_token}" }
      allow(response).to receive_messages(code: '200', body: '{}')
      allow(Integrations::Clients::HTTP).to receive(:get).and_return(response)

      client.verify_token(valid_token)

      expect(Integrations::Clients::HTTP).to have_received(:get)
        .with(anything, headers: hash_including(expected_header))
    end

    context 'with an unmapped response code' do
      before do
        allow(response).to receive_messages(code: '100', body: '')
        allow(Integrations::Clients::HTTP).to receive(:get).and_return(response)
      end

      it 'returns unknown, never inactive' do
        result = client.verify_token(valid_token)

        expect(result.unknown?).to be(true)
      end
    end
  end
end
