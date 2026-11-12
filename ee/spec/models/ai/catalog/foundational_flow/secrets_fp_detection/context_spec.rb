# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Ai::Catalog::FoundationalFlow::SecretsFpDetection::Context, feature_category: :duo_agent_platform do
  describe '.call' do
    subject(:context) do
      described_class.call(
        runtime_context: Ai::DuoWorkflows::AdditionalContext::RuntimeContext.new(
          project: nil, resource: resource, goal: nil, primary_branch: nil
        )
      )
    end

    let_it_be(:project) { create(:project) }

    let(:token_value) { 'fake-secret' }
    let(:vulnerability) do
      create(:vulnerability, report_type: :secret_detection, project: project, findings: [
        build(:vulnerabilities_finding, :identifier, report_type: :secret_detection, project: project,
          raw_metadata: { 'raw_source_code_extract' => token_value }.to_json)
      ])
    end

    let(:resource) { vulnerability }

    it 'returns the secret value' do
      expect(context).to eq("secret_value" => token_value)
    end

    it 'matches the agent_platform_secrets_fp_detection_context schema' do
      schema = JSONSchemer.schema(Rails.root.join(
        'app/validators/json_schemas/agent_platform/agent_platform_secrets_fp_detection_context/1.0.0.json'
      ))

      expect(schema.valid?(context)).to be(true)
    end

    context 'when the resource is not a vulnerability' do
      let(:resource) { build_stubbed(:merge_request) }

      it { is_expected.to eq({}) }
    end

    context 'when the vulnerability has no finding' do
      let(:resource) { create(:vulnerability, project: project) }

      it { is_expected.to eq({}) }
    end

    context 'when the finding secret is redacted' do
      before do
        create(:vulnerability_representation_information, vulnerability: vulnerability, removed_from_code: true)
      end

      it { is_expected.to eq({}) }
    end

    context 'when the finding has a blank token value' do
      let(:token_value) { '   ' }

      it { is_expected.to eq({}) }
    end
  end
end
