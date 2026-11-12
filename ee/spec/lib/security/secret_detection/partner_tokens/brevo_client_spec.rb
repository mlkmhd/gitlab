# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Security::SecretDetection::PartnerTokens::BrevoClient, feature_category: :secret_detection do
  let(:client) { described_class.new }
  let(:valid_token) { "xkeysib-aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa-aaaaaaaaaaaaaaaa" }
  let(:response) { instance_double(Net::HTTPResponse) }

  it_behaves_like 'a partner token client', http_method: :get

  describe '#verify_token' do
    before do
      allow(Integrations::Clients::HTTP).to receive(:get).and_return(response)
    end

    context 'when Brevo returns the account' do
      before do
        allow(response).to receive_messages(code: '200', body: '{}')
      end

      it 'returns active' do
        expect(client.verify_token(valid_token).active?).to be(true)
      end
    end

    context 'when Brevo does not know the key' do
      before do
        allow(response).to receive_messages(code: '401', body: '{"message":"Key not found","code":"unauthorized"}')
      end

      it 'returns inactive' do
        expect(client.verify_token(valid_token).inactive?).to be(true)
      end
    end

    context 'when Brevo rejects the request address' do
      before do
        allow(response).to receive_messages(
          code: '401',
          body: '{"message":"We have detected you are using an unrecognised IP address 203.0.113.9. ' \
            'If you performed this action make sure to add the new IP address in this link: ' \
            'https://app.brevo.com/security/authorised_ips","code":"unauthorized"}'
        )
      end

      it 'returns unknown, since the key may be live behind an IP allow-list' do
        result = client.verify_token(valid_token)

        expect(result.unknown?).to be(true)
        expect(result.inactive?).to be(false)
      end
    end

    context 'when a 401 body is not JSON' do
      before do
        allow(response).to receive_messages(code: '401', body: '<html>Unauthorized</html>')
      end

      it 'returns unknown instead of raising' do
        expect(client.verify_token(valid_token).unknown?).to be(true)
      end
    end

    context 'when a 401 body is JSON without a message' do
      before do
        allow(response).to receive_messages(code: '401', body: '{"code":"unauthorized"}')
      end

      it 'returns unknown' do
        expect(client.verify_token(valid_token).unknown?).to be(true)
      end
    end

    context 'when a 401 body is JSON but not an object' do
      before do
        allow(response).to receive_messages(code: '401', body: '[]')
      end

      it 'returns unknown instead of raising' do
        expect(client.verify_token(valid_token).unknown?).to be(true)
      end
    end

    context 'when the account needs activation or credits' do
      before do
        allow(response).to receive_messages(code: '402', body: '')
      end

      it 'returns unknown' do
        expect(client.verify_token(valid_token).unknown?).to be(true)
      end
    end

    context 'when the key is restricted to other resources' do
      before do
        allow(response).to receive_messages(code: '403', body: '')
      end

      it 'returns unknown' do
        expect(client.verify_token(valid_token).unknown?).to be(true)
      end
    end

    context 'when Brevo rate limits the request' do
      before do
        allow(response).to receive_messages(code: '429', body: '')
      end

      it 'raises RateLimitError' do
        expect { client.verify_token(valid_token) }.to raise_error(described_class::RateLimitError)
      end
    end

    context 'when Brevo reports a service error' do
      before do
        allow(response).to receive_messages(code: '500', body: '')
      end

      it 'raises NetworkError' do
        expect { client.verify_token(valid_token) }.to raise_error(described_class::NetworkError)
      end
    end

    it 'sends the key and the content type Brevo requires' do
      allow(response).to receive_messages(code: '200', body: '{}')

      client.verify_token(valid_token)

      expect(Integrations::Clients::HTTP).to have_received(:get)
        .with(anything, headers: hash_including('api-key' => valid_token, 'Content-Type' => 'application/json'))
    end

    context 'with an unmapped response code' do
      before do
        allow(response).to receive_messages(code: '100', body: '')
      end

      it 'returns unknown, never inactive' do
        expect(client.verify_token(valid_token).unknown?).to be(true)
      end
    end
  end
end
