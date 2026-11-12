# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Gitlab::Duo::RiskAssessment, feature_category: :dap_code_review do
  describe '.available?' do
    let_it_be(:project) { create(:project) }

    let(:stage_check_available) { true }

    subject { described_class.available?(project) }

    before do
      project.project_setting.update!(duo_foundational_flows_enabled: true)
      allow(::Gitlab::Llm::StageCheck).to receive(:available?)
        .with(project, :duo_workflow).and_return(stage_check_available)
    end

    context 'when the risk_classification flow is enabled for the project' do
      let_it_be(:catalog_item) { create(:ai_catalog_item, :risk_classification_v1) }
      let_it_be(:enabled_foundational_flow) do
        create(:ai_catalog_enabled_foundational_flow, :for_project, project: project, catalog_item: catalog_item)
      end

      it { is_expected.to be true }

      # Enabling the flow requires the flag at that point in time, but nothing
      # re-syncs enabled_foundational_flows if the flag is disabled afterwards.
      context 'when the feature flag is disabled after the flow was enabled' do
        before do
          stub_feature_flags(duo_mr_risk_classification: false)
        end

        it { is_expected.to be false }
      end

      context 'when duo_foundational_flows_enabled is false' do
        before do
          project.project_setting.update!(duo_foundational_flows_enabled: false)
        end

        it { is_expected.to be false }
      end

      context 'when StageCheck returns false' do
        let(:stage_check_available) { false }

        it { is_expected.to be false }
      end

      context 'with a request store', :request_store do
        let_it_be(:other_project) { create(:project) }

        it 'caches per project' do
          expect(::Gitlab::Llm::StageCheck).to receive(:available?).with(project, :duo_workflow).once.and_return(true)

          expect(Array.new(2) { described_class.available?(project) }).to all(be true)
          expect(described_class.available?(other_project)).to be false
        end
      end
    end

    context 'when the risk_classification flow is not enabled for the project' do
      it { is_expected.to be false }
    end

    context 'when the risk_classification flow definition does not exist' do
      before do
        allow(::Ai::Catalog::FoundationalFlow).to receive(:risk_classification_v1).and_return(nil)
      end

      it { is_expected.to be false }
    end

    context 'with a request store', :request_store do
      it 'checks availability once per project' do
        expect(::Gitlab::Llm::StageCheck).not_to receive(:available?)
        expect(project).to receive(:duo_foundational_flows_enabled).once.and_call_original

        expect(Array.new(2) { described_class.available?(project) }).to all(be false)
      end
    end
  end
end
