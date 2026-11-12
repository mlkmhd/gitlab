# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Gitlab::Duo::RecommendReviewers, feature_category: :code_review_workflow do
  describe '.available?' do
    let_it_be_with_refind(:project) { create(:project) }
    let_it_be(:foundational_flow) { ::Ai::Catalog::FoundationalFlow.recommend_reviewers_v1 }

    let(:stage_check_available) { true }

    subject(:available) { described_class.available?(project) }

    before do
      project.project_setting.update!(duo_foundational_flows_enabled: true)
      allow(::Gitlab::Llm::StageCheck).to receive(:available?)
        .with(project, :duo_workflow).and_return(stage_check_available)
    end

    context 'when the recommend_reviewers flow is enabled for the project' do
      before do
        item = create(:ai_catalog_item, :with_foundational_flow_reference,
          foundational_flow_reference: 'recommend_reviewers/v1')
        create(:ai_catalog_enabled_foundational_flow, :for_project, project: project, catalog_item: item)
      end

      it { is_expected.to be true }

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
    end

    context 'when the recommend_reviewers flow is not enabled for the project' do
      it { is_expected.to be false }
    end

    context 'when the recommend_reviewers flow is not defined' do
      before do
        allow(::Ai::Catalog::FoundationalFlow).to receive(:recommend_reviewers_v1).and_return(nil)
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
