# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Gitlab::Llm::Concerns::ExponentialBackoff, feature_category: :ai_abstraction_layer do
  let(:body) { { 'test' => 'test' } }
  let(:dummy_class) do
    Class.new do
      include Gitlab::Llm::Concerns::Logger

      def dummy_method(response_caller)
        retry_with_exponential_backoff do
          response_caller.call
        end
      end

      include Gitlab::Llm::Concerns::ExponentialBackoff
    end
  end

  let(:service) { dummy_class.new }
  let(:response) { instance_double(Net::HTTPResponse, body: body.to_json) }
  let(:success) do
    instance_double(HTTParty::Response,
      code: 200, success?: true, parsed_response: body,
      response: response, server_error?: false, too_many_requests?: false
    )
  end

  let(:too_many_requests_error) do
    rate_limited_response(headers: {})
  end

  let(:auth_error) do
    instance_double(HTTParty::Response,
      code: 401, success?: false, parsed_response: body,
      response: response, server_error?: false, too_many_requests?: false
    )
  end

  let(:empty_response) do
    instance_double(HTTParty::Response, response: nil)
  end

  let(:no_content_response) do
    instance_double(HTTParty::Response,
      code: 204,
      response: Net::HTTPNoContent.new("1.1", "204", "No Content"),
      server_error?: false, too_many_requests?: false
    )
  end

  let(:server_error) do
    instance_double(HTTParty::Response,
      code: 503, success?: false, parsed_response: body,
      response: response, server_error?: true, too_many_requests?: false
    )
  end

  let(:response_caller) { -> { success } }

  def rate_limited_response(headers:)
    instance_double(HTTParty::Response,
      code: 429, success?: false, parsed_response: body,
      response: response, server_error?: false, too_many_requests?: true,
      headers: headers
    )
  end

  subject { service.dummy_method(response_caller) }

  it_behaves_like 'has circuit breaker' do
    let(:service) { dummy_class.new }
    subject { service.dummy_method(response_caller) }
  end

  describe '.retry_with_exponential_backoff' do
    let(:max_retries) { described_class::MAX_RETRIES }

    context 'when the function succeeds on the first try' do
      it 'calls the function once and returns its result' do
        expect(response_caller).to receive(:call).once.and_call_original

        expect(subject).to be_success
      end
    end

    context 'when a custom retry function is not defined' do
      let(:blocked_body) { { "safetyAttributes" => { "blocked" => true } } }
      let(:blocked_response) { instance_double(Net::HTTPResponse, body: blocked_body.to_json) }
      let(:success_but_content_blocked) do
        instance_double(HTTParty::Response,
          code: 200, success?: true, parsed_response: blocked_body,
          response: blocked_response, server_error?: false, too_many_requests?: false
        )
      end

      it 'calls the function once and returns its result' do
        expect(response_caller).to receive(:call).once.and_call_original

        expect(subject).to be_success
      end
    end

    context 'when a custom retry function is defined' do
      before do
        dummy_class.define_method(:retry_immediately?) do |response|
          parsed_response = if response.parsed_response.is_a?(Hash)
                              response.parsed_response
                            else
                              Gitlab::Json::SafeParser.parse(response.parsed_response)
                            end

          parsed_response.dig("safetyAttributes", "blocked")
        end
      end

      let(:body) { { "safetyAttributes" => { "blocked" => false } } }

      context 'when the function succeeds and is not content blocked' do
        it 'calls the function once and returns its result' do
          expect(subject).to be_success
        end
      end

      context 'when the function succeeds but the content was blocked' do
        let(:blocked_body) { { "safetyAttributes" => { "blocked" => true } } }
        let(:blocked_response) { instance_double(Net::HTTPResponse, body: blocked_body.to_json) }
        let(:success_but_content_blocked) do
          instance_double(HTTParty::Response,
            code: 200, success?: true, parsed_response: blocked_body,
            response: blocked_response, server_error?: false, too_many_requests?: false
          )
        end

        before do
          stub_const("#{described_class.name}::INITIAL_DELAY", 0.0)
          allow(Random).to receive(:rand).and_return(0.001)
          allow(response_caller).to receive(:call).and_return(success_but_content_blocked, success)
        end

        it 'retries the function with an exponential backoff until it succeeds' do
          expect(subject).to be_success
          expect(Random).to have_received(:rand).once
          expect(response_caller).to have_received(:call).exactly(2).times
        end

        it 'raises a RateLimitError if the maximum number of retries is exceeded' do
          allow(response_caller).to receive(:call).and_return(success_but_content_blocked).exactly(max_retries).times

          expect do
            subject
          end.to raise_error(described_class::RateLimitError, "Maximum number of retries (#{max_retries}) exceeded.")

          expect(response_caller).to have_received(:call).exactly(max_retries).times
        end
      end
    end

    context 'when the function response is an error' do
      before do
        stub_const("#{described_class.name}::INITIAL_DELAY", 0.0)
        allow(Random).to receive(:rand).and_return(0.001)
      end

      it 'retries the function with an exponential backoff until it succeeds' do
        allow(response_caller).to receive(:call).and_return(too_many_requests_error, success)

        expect(subject).to be_success
        expect(Random).to have_received(:rand).once
        expect(response_caller).to have_received(:call).exactly(2).times
      end

      it 'raises a RateLimitError if the maximum number of retries is exceeded' do
        allow(response_caller).to receive(:call).and_return(too_many_requests_error).exactly(max_retries).times

        expect do
          subject
        end.to raise_error(described_class::RateLimitError, "Maximum number of retries (#{max_retries}) exceeded.")

        expect(response_caller).to have_received(:call).exactly(max_retries).times
      end

      context 'without rate limit error' do
        it 'returns error message' do
          allow(response_caller).to receive(:call).and_return(auth_error).once

          expect(subject).to eq(auth_error)
          expect(response_caller).to have_received(:call).once
        end
      end
    end

    context 'when the AI Gateway rejected the request with its own rate limit' do
      let(:response_caller) do
        -> {
          rate_limited_response(headers: { 'X-GitLab-Rate-Limit' => 'code_suggestions_actor_limit',
                                           'Retry-After' => '1' })
        }
      end

      it 'raises at once without retrying or sleeping' do
        allow(response_caller).to receive(:call).and_call_original
        expect(service).not_to receive(:sleep)

        expect { subject }.to raise_error(
          described_class::RateLimitError, 'Rate limited by the AI Gateway (code_suggestions_actor_limit)'
        )
        expect(response_caller).to have_received(:call).once
      end

      it 'logs the rate limit name as its own field' do
        expect(service).to receive(:log_info).with(
          hash_including(event_name: 'gateway_rate_limited', rate_limit: 'code_suggestions_actor_limit')
        ).and_call_original

        expect { subject }.to raise_error(described_class::RateLimitError)
      end
    end

    context 'when a rate limited response carries Retry-After' do
      let(:retry_after) { '3' }

      before do
        allow(service).to receive(:sleep)
        allow(response_caller).to receive(:call)
          .and_return(rate_limited_response(headers: { 'Retry-After' => retry_after }), success)
      end

      it 'waits the advertised seconds instead of the exponential delay' do
        expect(subject).to be_success
        expect(service).to have_received(:sleep).with(3)
      end

      context 'when Retry-After is above the cap' do
        let(:retry_after) { '600' }

        it 'waits the capped delay' do
          expect(subject).to be_success
          expect(service).to have_received(:sleep).with(described_class::MAX_RETRY_AFTER)
        end
      end

      context 'when Retry-After is an HTTP date' do
        let(:retry_after) { 'Wed, 21 Oct 2026 07:28:00 GMT' }

        before do
          allow(Random).to receive(:rand).and_return(0)
        end

        it 'falls back to the exponential delay' do
          expect(subject).to be_success
          expect(service).to have_received(:sleep).with(2.0)
        end
      end

      context 'when a later rate limited response carries no Retry-After' do
        before do
          allow(Random).to receive(:rand).and_return(0)
          allow(response_caller).to receive(:call).and_return(
            rate_limited_response(headers: { 'Retry-After' => '10' }), too_many_requests_error, success
          )
        end

        it 'keeps the exponential delay independent of the advertised wait' do
          expect(subject).to be_success
          expect(service).to have_received(:sleep).with(10).ordered
          expect(service).to have_received(:sleep).with(4.0).ordered
        end
      end
    end

    context 'when the function response is empty' do
      it 'does not retry the function' do
        allow(response_caller).to receive(:call).and_return(empty_response)

        expect(subject).to be_nil
        expect(response_caller).to have_received(:call).once
      end
    end

    context 'when the function response is no content' do
      it 'does not retry the function' do
        allow(response_caller).to receive(:call).and_return(no_content_response)

        expect(subject).to eq(no_content_response)
        expect(response_caller).to have_received(:call).once
      end
    end

    context 'when the function response is a server error' do
      it 'returns a nil response' do
        allow(response_caller).to receive(:call).and_return(server_error)

        expect(subject).to be_nil
      end
    end
  end
end
