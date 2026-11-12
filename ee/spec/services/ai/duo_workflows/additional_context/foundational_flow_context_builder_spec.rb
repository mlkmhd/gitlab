# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Ai::DuoWorkflows::AdditionalContext::FoundationalFlowContextBuilder, feature_category: :duo_agent_platform do
  using RSpec::Parameterized::TableSyntax

  let(:runtime_context) do
    Ai::DuoWorkflows::AdditionalContext::RuntimeContext.new(
      project: nil, resource: build_stubbed(:merge_request), goal: nil, primary_branch: nil
    )
  end

  let(:fields) { { 'duo_code_review_bot_name' => 'duo-bot' } }
  let(:resolver) { ->(runtime_context:) { fields } } # rubocop:disable Lint/UnusedBlockArgument -- matches the resolver contract
  let(:default_category) { 'agent_platform_code_review_context' }
  let(:context_category_alias) { nil }
  let(:flow) do
    Ai::Catalog::FoundationalFlow.new(
      foundational_flow_reference: 'code_review/v1',
      additional_context_resolver: resolver,
      context_category_alias: context_category_alias
    )
  end

  subject(:context) { described_class.new(flow: flow).build(runtime_context: runtime_context) }

  describe '.context_categories_for' do
    subject(:categories) { described_class.context_categories_for(flow) }

    it 'returns the category derived from the flow reference' do
      expect(categories).to eq([default_category])
    end

    context 'when the flow sets a context_category_alias' do
      let(:context_category_alias) { 'code_review_context' }

      it 'also returns the aliased category' do
        expect(categories).to eq([default_category, 'code_review_context'])
      end
    end
  end

  describe 'categories of the registered flows' do
    # Add a row when a foundational flow is registered: the last examples fail until then.
    where(:reference, :categories) do
      'code_review/v1'                                    | %w[agent_platform_code_review_context code_review_context]
      'risk_classification/v1'                            | %w[agent_platform_risk_classification_context]
      'sast_fp_detection/v1'                              | %w[agent_platform_sast_fp_detection_context]
      'resolve_sast_vulnerability/v1'                     | %w[agent_platform_resolve_sast_vulnerability_context]
      'developer/v1'                                      | %w[agent_platform_developer_context]
      'fix_pipeline/v1'                                   | %w[agent_platform_fix_pipeline_context]
      'convert_to_gl_ci/v1'                               | %w[agent_platform_convert_to_gl_ci_context]
      'recommend_reviewers/v1'                            | %w[agent_platform_recommend_reviewers_context]
      'secrets_fp_detection/v1'                           |
        %w[agent_platform_secrets_fp_detection_context secret_detection_context]
      'resolve_dependency_bump/experimental'              | %w[agent_platform_resolve_dependency_bump_context]
      'security_review/v1'                                | %w[agent_platform_security_review_context]
      'bl_security/experimental'                          | %w[agent_platform_bl_security_context]
      'business_context_security_guidelines/experimental' |
        %w[agent_platform_business_context_security_guidelines_context]
      'workplan/v1'                                       | %w[agent_platform_workplan_context]
      'readiness_score/v1'                                | %w[agent_platform_readiness_score_context]
      'slack_assistant/v1'                                | %w[agent_platform_slack_assistant_context]
      'skillguard_scan/v1'                                | %w[agent_platform_skillguard_scan_context]
    end

    with_them do
      it 'maps the flow reference to its derived and aliased categories' do
        expect(described_class.context_categories[reference]).to eq(categories)
      end

      it 'reserves the categories of the flow' do
        expect(described_class.reserved_context_categories).to include(*categories)
      end

      it 'has a row for every registered flow' do
        expect(self.class.all_params.map(&:first)).to match_array(described_class.context_categories.keys)
      end

      it 'reserves no category missing from the table' do
        expect(described_class.reserved_context_categories).to match_array(self.class.all_params.flat_map(&:last))
      end
    end
  end

  describe '#build' do
    it 'wraps the fields under the category derived from the flow reference' do
      expect(context).to contain_exactly(
        Ai::DuoWorkflows::AdditionalContext::Envelope.wrap(category: default_category, fields: fields)
      )
    end

    it 'calls the resolver with the context' do
      expect(resolver).to receive(:call).with(runtime_context: runtime_context).and_call_original

      context
    end

    context 'when the flow sets a context_category_alias' do
      let(:context_category_alias) { 'code_review_context' }

      it 'wraps the fields under both the derived and the aliased category' do
        expect(context).to contain_exactly(
          Ai::DuoWorkflows::AdditionalContext::Envelope.wrap(category: default_category, fields: fields),
          Ai::DuoWorkflows::AdditionalContext::Envelope.wrap(category: 'code_review_context', fields: fields)
        )
      end
    end

    context 'when the context_category_alias matches the derived category' do
      let(:context_category_alias) { default_category }

      it 'wraps the fields only once' do
        expect(context).to contain_exactly(
          Ai::DuoWorkflows::AdditionalContext::Envelope.wrap(category: default_category, fields: fields)
        )
      end
    end

    context 'when the flow has no additional_context_resolver' do
      let(:resolver) { nil }

      it { is_expected.to eq([]) }
    end

    context 'when the resolver returns no fields' do
      where(:fields) { [nil, {}] }

      with_them do
        it { is_expected.to eq([]) }
      end
    end
  end
end
