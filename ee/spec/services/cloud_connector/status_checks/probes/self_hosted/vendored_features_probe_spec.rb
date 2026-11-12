# frozen_string_literal: true

require 'spec_helper'

RSpec.describe CloudConnector::StatusChecks::Probes::SelfHosted::VendoredFeaturesProbe, feature_category: :duo_service_infra do
  let(:probe) { described_class.new }

  describe '#execute' do
    context 'when no feature setting is vendored' do
      before do
        create(:ai_feature_setting, feature: :code_completions, provider: :self_hosted)
      end

      it 'returns a successful result' do
        result = probe.execute

        expect(result).to be_a(CloudConnector::StatusChecks::Probes::ProbeResult)
        expect(result.success?).to be(true)
        expect(result.message).to eq('No feature uses a GitLab-managed model.')
      end
    end

    context 'when feature settings are vendored' do
      before do
        create(:ai_feature_setting, feature: :duo_chat, provider: :vendored)
        create(:ai_feature_setting, feature: :code_completions, provider: :vendored)
        create(:ai_feature_setting, feature: :code_generations, provider: :self_hosted)
        create(:ai_feature_setting, feature: :embeddings_code, provider: :vendored)
      end

      it 'names each vendored feature that Model selection lists by its title' do
        result = probe.execute

        expect(result.success?).to be(false)
        expect(result.message).to eq(
          'GitLab-managed models are not available with an offline cloud license. ' \
            'Assign a self-hosted model in Model selection to these features: Code Completion, General Chat.'
        )
      end
    end
  end
end
