# frozen_string_literal: true

require "spec_helper"

RSpec.describe Ai::Catalog::FoundationalFlow::RiskClassification::Context, feature_category: :duo_agent_platform do
  describe '.call' do
    subject(:context) do
      described_class.call(
        runtime_context: Ai::DuoWorkflows::AdditionalContext::RuntimeContext.new(
          project: nil, resource: resource, goal: nil, primary_branch: nil
        )
      )
    end

    let(:resource) { build_stubbed(:merge_request) }
    let(:domains) { ::Gitlab::Duo::RiskAssessment::Domain.all }
    let(:payload) { context }

    it 'sends every domain the flow answers a claim about' do
      expect(payload['domains'].pluck('name')).to match_array(domains.map(&:name))
      expect(payload['domains']).to all(include('description' => be_present))
    end

    it 'is valid against the agent_platform_risk_classification_context schema' do
      schema_path = Rails.root.join(
        'app/validators/json_schemas/agent_platform/agent_platform_risk_classification_context/1.0.0.json'
      )
      schema = JSONSchemer.schema(schema_path)

      expect(schema.valid?(payload)).to be(true), schema.validate(payload).to_a.inspect
    end
  end
end
