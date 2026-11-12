# frozen_string_literal: true

RSpec.describe Bitbucket::ApiConnection do
  let(:logger) { instance_double(Logger, info: nil) }
  let(:http_client) { class_double(HTTParty) }

  describe '#get' do
    subject(:connection) do
      described_class.new(
        { email: 'user@example.com', api_token: 'token123', logger: logger },
        http_client: http_client
      )
    end

    it 'performs a GET request through the injected http_client with basic auth' do
      expect(connection).to receive(:retry_with_exponential_backoff).and_call_original

      expect(http_client)
        .to receive(:get)
        .with(
          'https://api.bitbucket.org/2.0/user',
          {
            basic_auth: { username: 'user@example.com', password: 'token123' },
            headers: { 'Accept' => 'application/json' },
            query: { page: 1 }
          }
        )
        .and_return(
          instance_double(HTTParty::Response, code: 200, success?: true, parsed_response: {})
        )

      connection.get('/user', page: 1)
    end

    it 'logs the retries and raises an error if it does not succeed on retry' do
      httparty_response = instance_double(Net::HTTPResponse, code: '429')
      allow(http_client).to receive(:get).and_raise(HTTParty::ResponseError.new(httparty_response))
      stub_const('Bitbucket::ExponentialBackoff::INITIAL_DELAY', 0.0)
      allow(Random).to receive(:rand).and_return(0.001)

      expect(logger).to receive(:info)
        .with(message: /Retrying in .+ seconds due to/)
        .twice

      expect { connection.get('/users') }.to raise_error(Bitbucket::ExponentialBackoff::RateLimitError)
    end

    context 'when the API returns an error response' do
      it 'raises InvalidResponse with the HTTP status code' do
        response = instance_double(
          HTTParty::Response,
          code: 401,
          success?: false,
          parsed_response: { 'error' => { 'message' => 'Unauthorized' } },
          body: '{"error": {"message": "Unauthorized"}}'
        )
        allow(http_client).to receive(:get).and_return(response)

        expect { connection.get('/user') }
          .to raise_error(Bitbucket::Error::InvalidResponse) do |error|
            expect(error.message).to eq('Unauthorized')
            expect(error.http_status).to eq(401)
          end
      end

      it 'extracts error message from parsed JSON response' do
        response = instance_double(
          HTTParty::Response,
          code: 404,
          success?: false,
          parsed_response: { 'error' => { 'message' => 'Repository not found' } },
          body: '{"error": {"message": "Repository not found"}}'
        )
        allow(http_client).to receive(:get).and_return(response)

        expect { connection.get('/user') }
          .to raise_error(Bitbucket::Error::InvalidResponse, 'Repository not found')
      end

      it 'falls back to HTTP status when parsed response has no error message' do
        response = instance_double(
          HTTParty::Response,
          code: 403,
          success?: false,
          parsed_response: {},
          body: '{}'
        )
        allow(http_client).to receive(:get).and_return(response)

        expect { connection.get('/user') }
          .to raise_error(Bitbucket::Error::InvalidResponse, 'HTTP 403')
      end

      it 'includes response body when parsed response is not a Hash (e.g., HTML error page)' do
        response = instance_double(
          HTTParty::Response,
          code: 403,
          success?: false,
          parsed_response: '<html>Forbidden</html>',
          body: '<html>Forbidden</html>'
        )
        allow(http_client).to receive(:get).and_return(response)

        expect { connection.get('/user') }
          .to raise_error(Bitbucket::Error::InvalidResponse, 'HTTP 403: <html>Forbidden</html>')
      end
    end
  end

  describe 'http_client requirement' do
    it 'raises ArgumentError when no http_client is provided' do
      expect { described_class.new({ email: 'user@example.com', api_token: 'token123' }) }
        .to raise_error(ArgumentError, /missing keyword: :http_client/)
    end
  end

  describe 'null logger fallback' do
    subject(:connection) do
      described_class.new({ email: 'user@example.com', api_token: 'token123' }, http_client: http_client)
    end

    it 'does not raise when no logger is injected and a retry fires' do
      httparty_response = instance_double(Net::HTTPResponse, code: '429')
      allow(http_client).to receive(:get).and_raise(HTTParty::ResponseError.new(httparty_response))
      stub_const('Bitbucket::ExponentialBackoff::INITIAL_DELAY', 0.0)
      allow(Random).to receive(:rand).and_return(0.001)

      expect { connection.get('/user') }.to raise_error(Bitbucket::ExponentialBackoff::RateLimitError)
    end
  end

  describe '#refresh_if_expired!' do
    subject(:connection) do
      described_class.new({ email: 'user@example.com', api_token: 'token123' }, http_client: http_client)
    end

    it 'is a no-op because API token credentials do not expire' do
      expect(connection.refresh_if_expired!).to be_nil
    end
  end
end
