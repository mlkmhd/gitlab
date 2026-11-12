# frozen_string_literal: true

require 'spec_helper'

RSpec.describe ::Ai::ModelSelection::FetchModelDefinitionsService, :use_clean_rails_redis_caching,
  feature_category: :"self-hosted_models" do
  let(:endpoint_url) { "https://cloud.gitlab.com/ai/v1/models%2Fdefinitions" }
  let(:gateway_request) { a_request(:get, endpoint_url) }

  let(:model_definitions) do
    {
      'models' => [
        { 'name' => 'Claude Sonnet', 'identifier' => 'claude_sonnet' }
      ],
      'unit_primitives' => [
        {
          'feature_setting' => 'duo_chat',
          'default_model' => 'claude-sonnet',
          'selectable_models' => %w[claude-sonnet],
          'beta_models' => []
        }
      ]
    }
  end

  let(:model_definitions_response) { model_definitions.to_json }

  let(:user) { nil }
  let(:initialized_class) { described_class.new(user) }

  subject(:service) { initialized_class.execute }

  before do
    allow(Gitlab::AiGateway).to receive(:public_headers).and_return({})
    allow(Gitlab::AiGateway).to receive(:push_feature_flag)
  end

  def execute_service
    described_class.new(user).execute
  end

  describe '#execute' do
    context 'when license is offline' do
      before do
        license = create(:license)
        allow(::License).to receive(:current).and_return(license)
        allow(license).to receive(:offline_cloud_license?).and_return(true)
      end

      it 'returns success ServiceResponse with nil payload' do
        expect(service).to be_success
        expect(service.payload).to be_nil
      end
    end

    context 'when ai_model_release state changes between requests' do
      before do
        stub_request(:get, endpoint_url)
          .to_return(status: 200, body: model_definitions_response, headers: { 'Content-Type' => 'application/json' })
        execute_service
      end

      it 'serves cached response when ai_model_release is enabled', :aggregate_failures do
        expect(service.payload).to eq(model_definitions)
        expect(gateway_request).to have_been_made.once
      end

      it 'makes a new request when ai_model_release is disabled (cache miss on different key)' do
        stub_feature_flags(ai_model_release: false)

        execute_service

        expect(gateway_request).to have_been_made.twice
      end
    end

    context 'when response is not cached' do
      context 'when API call is successful' do
        before do
          stub_request(:get, endpoint_url)
            .to_return(
              status: 200,
              body: model_definitions_response,
              headers: { 'Content-Type' => 'application/json' }
            )
        end

        it 'sends public headers in the request' do
          expect(Gitlab::AiGateway).to receive(:public_headers).with(
            user: user,
            unit_primitive_name: :code_suggestions,
            ai_feature_name: :code_suggestions
          ).and_return({})

          service
        end

        context 'when a user is provided' do
          let(:user) { build_stubbed(:user) }

          it 'sends public headers with the user' do
            expect(Gitlab::AiGateway).to receive(:public_headers).with(
              user: user,
              unit_primitive_name: :code_suggestions,
              ai_feature_name: :code_suggestions
            ).and_return({})

            service
          end
        end

        context 'when checking the ai_model_release feature flag header', :request_store do
          before do
            allow(Gitlab::AiGateway).to receive(:push_feature_flag).and_call_original
            allow(Gitlab::AiGateway).to receive(:public_headers).and_call_original
          end

          it 'includes ai_model_release in the x-gitlab-enabled-feature-flags header' do
            expect(Gitlab::HTTP).to receive(:get).with(
              endpoint_url,
              hash_including(
                headers: hash_including('x-gitlab-enabled-feature-flags' => a_string_including('ai_model_release'))
              )
            ).and_call_original

            service
          end

          context 'when ai_model_release is disabled' do
            before do
              stub_feature_flags(ai_model_release: false)
            end

            it 'does not include ai_model_release in the x-gitlab-enabled-feature-flags header' do
              expect(Gitlab::HTTP).to receive(:get).with(
                endpoint_url,
                hash_including(
                  headers: hash_including(
                    'x-gitlab-enabled-feature-flags' => satisfy { |value| value.exclude?('ai_model_release') }
                  )
                )
              ).and_call_original

              service
            end
          end
        end
      end

      context 'when API call returns error' do
        let(:error_message) { "Received error 401 from AI gateway when fetching model definitions" }

        before do
          stub_request(:get, endpoint_url)
            .to_return(
              status: 401,
              body: "{\"error\":\"No authorization header presented\"}",
              headers: { 'Content-Type' => 'application/json' }
            )
        end

        it 'logs the error and returns error ServiceResponse' do
          expect(initialized_class).to receive(:log_error)

          expect(service).to be_error
          expect(service.message).to eq(error_message)
        end
      end

      context 'when API call raises network error (SocketError)' do
        before do
          allow(Gitlab::HTTP).to receive(:get).and_raise(SocketError.new('Connection failed'))
        end

        it 'handles error gracefully and returns error ServiceResponse' do
          expect(service).to be_error
          expect(service.message).to eq('Failed to fetch model definitions')
        end

        it 'logs the exception class' do
          expect(Gitlab::AppLogger).to receive(:error).with(
            message: 'Error fetching model definitions: Connection failed',
            exception_class: 'SocketError',
            ai_component: 'model_selection'
          )

          service
        end
      end

      context 'when API call raises timeout error (Net::OpenTimeout)' do
        before do
          allow(Gitlab::HTTP).to receive(:get).and_raise(Net::OpenTimeout.new('Request timeout'))
        end

        it 'handles timeout gracefully and returns error ServiceResponse' do
          expect(service).to be_error
          expect(service.message).to eq('Failed to fetch model definitions')
        end
      end

      context 'when API call raises unexpected StandardError' do
        before do
          allow(Gitlab::HTTP).to receive(:get).and_raise(StandardError.new('Unexpected error'))
        end

        it 'handles unexpected error gracefully and returns error ServiceResponse' do
          expect(service).to be_error
          expect(service.message).to eq('Failed to fetch model definitions')
        end
      end
    end
  end

  describe 'local development behavior with respect to cache' do
    context 'when FETCH_MODEL_SELECTION_DATA_FROM_LOCAL environment variable is set' do
      let(:local_endpoint_url) { 'http://local-gateway.com/v1/models%2Fdefinitions' }

      before do
        allow(::Gitlab::AiGateway).to receive(:url).and_return('http://local-gateway.com')
      end

      %w[1 true True TRUE].each do |truthy_value|
        context "with value set to '#{truthy_value}'" do
          before do
            stub_env('FETCH_MODEL_SELECTION_DATA_FROM_LOCAL', truthy_value)
            stub_request(:get, local_endpoint_url)
              .to_return(
                status: 200,
                body: model_definitions_response,
                headers: { 'Content-Type' => 'application/json' }
              )
          end

          it 'calls the local AI Gateway for every request' do
            expect(Gitlab::HTTP).to receive(:get).with(
              local_endpoint_url,
              hash_including(allow_local_requests: true)
            ).twice.and_call_original

            2.times { execute_service }
          end
        end
      end

      ['0', 'false', 'False', 'FALSE', '', nil].each do |falsy_value|
        context "with value set to '#{falsy_value}'" do
          before do
            stub_env('FETCH_MODEL_SELECTION_DATA_FROM_LOCAL', falsy_value)
            stub_request(:get, endpoint_url)
              .to_return(
                status: 200,
                body: model_definitions_response,
                headers: { 'Content-Type' => 'application/json' }
              )
          end

          it 'uses and respects cache' do
            2.times { execute_service }

            expect(gateway_request).to have_been_made.once
          end
        end
      end
    end
  end

  describe 'endpoint behavior' do
    context 'when not in local development' do
      before do
        stub_env('FETCH_MODEL_SELECTION_DATA_FROM_LOCAL', nil)
      end

      it 'uses the cloud-connected endpoint URL' do
        stub_request(:get, "https://cloud.gitlab.com/ai/v1/models%2Fdefinitions")
          .to_return(
            status: 200,
            body: model_definitions_response,
            headers: { 'Content-Type' => 'application/json' }
          )

        expect(service).to be_success
      end
    end

    context 'when in local development' do
      let(:local_endpoint_url) { 'http://local-gateway.com/v1/models%2Fdefinitions' }

      before do
        stub_env('FETCH_MODEL_SELECTION_DATA_FROM_LOCAL', '1')
        allow(::Gitlab::AiGateway).to receive(:url).and_return('http://local-gateway.com')
      end

      it 'uses the local endpoint URL' do
        stub_request(:get, local_endpoint_url)
          .to_return(
            status: 200,
            body: model_definitions_response,
            headers: { 'Content-Type' => 'application/json' }
          )

        expect(service).to be_success
      end

      context 'when the AI Gateway returns an error' do
        before do
          stub_request(:get, local_endpoint_url).to_return(status: 401, body: '{}')
        end

        it 'returns the AI Gateway error', :aggregate_failures do
          expect(service).to be_error
          expect(service.message).to eq('Received error 401 from AI gateway when fetching model definitions')
        end
      end

      context 'when the request raises an error' do
        before do
          allow(Gitlab::HTTP).to receive(:get).and_raise(SocketError.new('Connection failed'))
        end

        it 'returns an error', :aggregate_failures do
          expect(service).to be_error
          expect(service.message).to eq('Failed to fetch model definitions')
        end
      end
    end
  end

  describe 'catalog caching' do
    let(:updated_model_definitions) do
      model_definitions.merge('models' => [{ 'name' => 'Claude Opus', 'identifier' => 'claude_opus' }])
    end

    context 'when no catalog is cached' do
      context 'when the AI Gateway responds' do
        before do
          stub_request(:get, endpoint_url)
            .to_return(status: 200, body: model_definitions_response, headers: { 'Content-Type' => 'application/json' })
        end

        it 'calls the AI Gateway once for later requests' do
          2.times { execute_service }

          expect(gateway_request).to have_been_made.once
        end
      end

      context 'when the AI Gateway returns an error' do
        before do
          stub_request(:get, endpoint_url).to_return(status: 401, body: '{}')
        end

        it 'does not cache the error' do
          2.times { execute_service }

          expect(gateway_request).to have_been_made.twice
        end
      end
    end

    context 'when the cached catalog has expired' do
      before do
        stub_request(:get, endpoint_url)
          .to_return(status: 200, body: model_definitions_response, headers: { 'Content-Type' => 'application/json' })
        execute_service
        WebMock.reset_executed_requests!

        travel(described_class::RESPONSE_CACHE_EXPIRATION + 1.second)
      end

      context 'when the AI Gateway responds' do
        before do
          stub_request(:get, endpoint_url)
            .to_return(
              status: 200,
              body: updated_model_definitions.to_json,
              headers: { 'Content-Type' => 'application/json' }
            )
        end

        it 'returns the updated catalog' do
          expect(service.payload).to eq(updated_model_definitions)
        end
      end

      shared_examples 'serving the expired catalog' do
        it 'returns the expired catalog to the request that retries', :aggregate_failures do
          expect(service).to be_success
          expect(service.payload).to eq(model_definitions)
        end

        it 'returns the expired catalog to later requests', :aggregate_failures do
          execute_service

          later_response = execute_service

          expect(later_response).to be_success
          expect(later_response.payload).to eq(model_definitions)
        end

        it 'calls the AI Gateway once' do
          3.times { execute_service }

          expect(gateway_request).to have_been_made.once
        end

        context 'when the retry window has passed' do
          it 'calls the AI Gateway again' do
            execute_service
            travel(described_class::RACE_CONDITION_TTL + 1.second)
            execute_service

            expect(gateway_request).to have_been_made.twice
          end
        end
      end

      context 'when the AI Gateway returns an error' do
        before do
          stub_request(:get, endpoint_url).to_return(status: 500, body: '{}')
        end

        it_behaves_like 'serving the expired catalog'
      end

      context 'when the AI Gateway times out' do
        before do
          stub_request(:get, endpoint_url).to_timeout
        end

        it_behaves_like 'serving the expired catalog'
      end
    end

    context 'when called more than once in one request', :request_store do
      context 'when a catalog is cached' do
        before do
          stub_request(:get, endpoint_url)
            .to_return(status: 200, body: model_definitions_response, headers: { 'Content-Type' => 'application/json' })
          execute_service
          RequestStore.clear!
        end

        it 'reads the cache once' do
          recorder = RedisCommands::Recorder.new(pattern: described_class::RESPONSE_CACHE_NAME) do
            3.times { execute_service }
          end

          expect(recorder.count).to eq(1)
        end
      end

      context 'when the AI Gateway times out' do
        before do
          stub_request(:get, endpoint_url).to_timeout
        end

        it 'calls the AI Gateway once' do
          3.times { execute_service }

          expect(gateway_request).to have_been_made.once
        end
      end
    end
  end
end
