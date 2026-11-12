# frozen_string_literal: true

require 'spec_helper'

RSpec.describe ::Ai::ModelSelection::UpsertInstanceFeatureSettingService, feature_category: :"self-hosted_models" do
  let_it_be(:user) { create(:user) }
  let(:feature) { :code_generations }
  let(:offered_model_ref) { 'openai_chatgpt_4o' }
  let(:model_definitions) do
    {
      'models' => [
        { 'name' => 'Claude Sonnet 3.5', 'identifier' => 'claude_sonnet_3_5' },
        { 'name' => 'Claude Sonnet 3.7', 'identifier' => 'claude_sonnet_3_7' },
        { 'name' => 'OpenAI Chat GPT 4o', 'identifier' => 'openai_chatgpt_4o' }
      ],
      'unit_primitives' => [
        {
          'feature_setting' => 'code_generations',
          'default_model' => 'claude_sonnet_3_5',
          'selectable_models' => %w[claude_sonnet_3_5 claude_sonnet_3_7 openai_chatgpt_4o],
          'beta_models' => []
        }
      ]
    }
  end

  let(:model_definitions_response) { model_definitions.to_json }

  include_context 'with the model selections fetch definition service as side-effect'

  subject(:response) { described_class.new(user, feature, offered_model_ref).execute }

  describe '#execute' do
    context 'when fetch model definitions is successful' do
      before do
        stub_request(:get, fetch_service_endpoint_url)
          .to_return(
            status: 200,
            body: model_definitions_response,
            headers: { 'Content-Type' => 'application/json' }
          )
      end

      context 'when feature setting update is successful' do
        context 'when feature setting is new' do
          it 'returns a success response with the feature setting' do
            expect { response }.to change { ::Ai::ModelSelection::InstanceModelSelectionFeatureSetting.count }.by(1)

            expect(response).to be_success
            expect(response.payload.persisted?).to be(true)
            expect(response.payload.offered_model_ref).to eq(offered_model_ref)
            expect(response.payload.offered_model_name).to eq('OpenAI Chat GPT 4o')
          end
        end

        context 'when feature setting is already persisted' do
          let!(:existing_setting) do
            create(:instance_model_selection_feature_setting, feature: feature)
          end

          it 'returns a success response with the feature setting' do
            expect { response }.not_to change { ::Ai::ModelSelection::InstanceModelSelectionFeatureSetting.count }

            existing_setting.reload

            expect(response).to be_success
            expect(response.payload.id).to eq(existing_setting.id)
            expect(existing_setting.offered_model_ref).to eq(offered_model_ref)
            expect(existing_setting.offered_model_name).to eq('OpenAI Chat GPT 4o')
          end
        end

        context 'when the inputted model ref is empty' do
          let(:offered_model_ref) { '' }

          it 'returns a success response with the feature setting' do
            expect(response).to be_success
            expect(response.payload.persisted?).to be(true)
            expect(response.payload.offered_model_ref).to be_empty
            expect(response.payload.offered_model_name).to be_empty
          end
        end

        context 'with recorded events' do
          it 'tracks event' do
            expect { response }
              .to trigger_internal_events('update_model_selection_feature')
                    .with(
                      user: user,
                      category: described_class.name,
                      additional_properties: {
                        label: offered_model_ref,
                        property: feature.to_s,
                        selection_scope_gid: nil
                      }
                    )
                    .and increment_usage_metrics('counts.count_total_update_model_selection_feature_weekly')
          end

          it 'records an audit event' do
            expect(Gitlab::Audit::Auditor).to receive(:audit) do |event|
              expect(event[:target]).to eq(response.payload)
            end.and_call_original

            response
          end
        end
      end

      context 'when a fetched catalog is given' do
        let(:catalog) do
          ::Ai::ModelSelection::ModelDefinitions.new(ServiceResponse.success(payload: model_definitions))
        end

        subject(:response) { described_class.new(user, feature, offered_model_ref, catalog: catalog).execute }

        it 'uses the given catalog instead of fetching the model definitions', :aggregate_failures do
          expect(::Ai::ModelSelection::ModelDefinitions).not_to receive(:fetch)

          expect(response).to be_success
          expect(response.payload.offered_model_ref).to eq(offered_model_ref)
        end
      end

      context 'when the selected model is unchanged' do
        let!(:existing_setting) do
          create(:instance_model_selection_feature_setting, feature: feature, offered_model_ref: offered_model_ref)
        end

        let!(:feature_setting) { create(:ai_feature_setting, feature: feature, provider: :vendored) }

        it 'returns the feature setting and does not fetch model definitions', :aggregate_failures do
          expect(::Ai::ModelSelection::ModelDefinitions).not_to receive(:fetch)

          expect(response).to be_success
          expect(response.payload).to eq(existing_setting)
        end

        it 'does not update the feature setting' do
          expect { response }.not_to change { existing_setting.reload.updated_at }
        end

        it 'does not audit or track an event', :aggregate_failures do
          expect(Gitlab::Audit::Auditor).not_to receive(:audit)

          expect { response }.not_to trigger_internal_events('update_model_selection_feature')
        end

        context 'when both the stored and the requested model ref are blank' do
          let(:offered_model_ref) { '' }
          let!(:existing_setting) do
            create(:instance_model_selection_feature_setting, feature: feature, offered_model_ref: nil,
              offered_model_name: nil)
          end

          it 'treats nil and empty string as the same selection', :aggregate_failures do
            expect(Gitlab::Audit::Auditor).not_to receive(:audit)

            expect(response).to be_success
            expect(existing_setting.reload.offered_model_ref).to be_nil
          end
        end

        context 'when the feature is currently self-hosted' do
          let!(:feature_setting) { create(:ai_feature_setting, feature: feature, provider: :self_hosted) }

          it 'updates the model selection', :aggregate_failures do
            expect(::Ai::ModelSelection::ModelDefinitions).to receive(:fetch).and_call_original

            expect { response }.to change { existing_setting.reload.updated_at }

            expect(response).to be_success
            expect(existing_setting.offered_model_ref).to eq(offered_model_ref)
          end

          it 'audits and tracks the model that became active', :aggregate_failures do
            expect(Gitlab::Audit::Auditor).to receive(:audit)
              .with(hash_including(message: "Feature #{feature} changed to vendored #{offered_model_ref}"))
              .and_call_original

            expect { response }.to trigger_internal_events('update_model_selection_feature').with(
              user: user,
              category: described_class.name,
              additional_properties: { label: offered_model_ref, property: feature.to_s, selection_scope_gid: nil }
            )
          end
        end

        context 'when there is no Ai::FeatureSetting for the feature' do
          let(:feature_setting) { nil }

          it 'does not skip the update', :aggregate_failures do
            expect(Gitlab::Audit::Auditor).to receive(:audit).and_call_original

            expect { response }.to change { existing_setting.reload.updated_at }
            expect(response).to be_success
          end
        end
      end

      context 'when feature setting update fails' do
        let(:offered_model_ref) { 'bad_ref' }
        let(:error_message) { "Offered model ref Selected model '#{offered_model_ref}' is not compatible" }

        it 'returns an error response with the feature setting and error message' do
          expect(response).to be_error
          expect(response.message).to include(error_message)
        end

        context 'with recorded events' do
          it 'does not record an audit event' do
            expect(Gitlab::Audit::Auditor).not_to receive(:audit)

            response
          end

          it 'does not track the event internally' do
            expect { response }.not_to trigger_internal_events('update_model_selection_feature')
          end
        end
      end
    end

    context 'when fetch model definitions fails' do
      let(:error_message) { 'Received error 401 from AI gateway when fetching model definitions' }

      before do
        stub_request(:get, fetch_service_endpoint_url)
          .to_return(
            status: 401,
            body: "{\"error\":\"No authorization header presented\"}",
            headers: { 'Content-Type' => 'application/json' }
          )
      end

      it 'returns an error response with the error message' do
        expect(response).to be_error
        expect(response.message).to eq(error_message)
      end

      context 'with recorded events' do
        it 'does not record an audit event' do
          expect(Gitlab::Audit::Auditor).not_to receive(:audit)

          response
        end

        it 'does not track the event internally' do
          expect { response }.not_to trigger_internal_events('update_model_selection_feature')
        end
      end
    end

    context 'with different features' do
      let(:feature) { :code_completions }
      let(:offered_model_ref) { 'claude_sonnet_3_5' }
      let(:model_definitions) do
        {
          'models' => [
            { 'name' => 'Claude Sonnet 3.5', 'identifier' => 'claude_sonnet_3_5' },
            { 'name' => 'Claude Sonnet 3.7', 'identifier' => 'claude_sonnet_3_7' }
          ],
          'unit_primitives' => [
            {
              'feature_setting' => 'code_completions',
              'default_model' => 'claude_sonnet_3_5',
              'selectable_models' => %w[claude_sonnet_3_5 claude_sonnet_3_7],
              'beta_models' => []
            }
          ]
        }
      end

      before do
        stub_request(:get, fetch_service_endpoint_url)
          .to_return(
            status: 200,
            body: model_definitions_response,
            headers: { 'Content-Type' => 'application/json' }
          )
      end

      it 'handles different features correctly' do
        expect(response).to be_success
        expect(response.payload.feature).to eq('code_completions')
        expect(response.payload.offered_model_ref).to eq(offered_model_ref)
        expect(response.payload.offered_model_name).to eq('Claude Sonnet 3.5')
      end
    end

    context 'with validation errors' do
      let(:offered_model_ref) { 'invalid_model_ref' }

      before do
        stub_request(:get, fetch_service_endpoint_url)
          .to_return(
            status: 200,
            body: model_definitions_response,
            headers: { 'Content-Type' => 'application/json' }
          )
      end

      it 'returns validation errors when model ref is invalid' do
        expect(response).to be_error
        expect(response.payload.persisted?).to be(false)
        expect(response.message).to include("Selected model 'invalid_model_ref' is not compatible")
      end
    end

    context 'when model definitions service returns empty payload' do
      let(:empty_model_definitions) { {} }
      let(:empty_model_definitions_response) { empty_model_definitions.to_json }

      before do
        stub_request(:get, fetch_service_endpoint_url)
          .to_return(
            status: 200,
            body: empty_model_definitions_response,
            headers: { 'Content-Type' => 'application/json' }
          )
      end

      it 'returns validation error for empty model definitions' do
        expect(response).to be_error
        expect(response.message).to include("No model definition given for validation")
      end
    end
  end
end
