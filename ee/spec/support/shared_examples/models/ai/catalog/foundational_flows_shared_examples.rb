# frozen_string_literal: true

# Evaluates the flow's precondition through the same FilterEvaluator a trigger uses, so a typo in the
# field, operator, or value fails the spec. Requires `flow` to be defined.
RSpec.shared_examples 'a foundational flow precondition' do |hook_scope:, field:, allowed:, denied:|
  let(:flow_trigger) { build_stubbed(:ai_flow_trigger) }

  before do
    allow(flow_trigger).to receive(:foundational_flow).and_return(flow)
  end

  def precondition_allows?(hook_scope, field, value)
    data = field.split('.').reverse.reduce(value) { |nested, key| { key => nested } }

    ::Ai::FlowTriggers::FilterEvaluator.new(flow_trigger: flow_trigger, hook_scope: hook_scope, data: data).allowed?
  end

  allowed.each do |value|
    it "allows the flow to run when #{field} is #{value}" do
      expect(precondition_allows?(hook_scope, field, value)).to be(true)
    end
  end

  denied.each do |value|
    it "prevents the flow from running when #{field} is #{value}" do
      expect(precondition_allows?(hook_scope, field, value)).to be(false)
    end
  end
end

RSpec.shared_examples 'flow with additional context resolver' do |resolver:, envelope_alias: nil|
  let(:resolved_context) do
    { 'foo' => 'bar' }
  end

  let(:runtime_context) do
    instance_double(::Ai::DuoWorkflows::AdditionalContext::RuntimeContext)
  end

  let(:additional_context) do
    ::Ai::DuoWorkflows::AdditionalContext::FoundationalFlowContextBuilder
      .new(flow: flow)
      .build(runtime_context: runtime_context)
  end

  let(:expected_categories) do
    [
      format(
        ::Ai::DuoWorkflows::AdditionalContext::FoundationalFlowContextBuilder::CONTEXT_CATEGORY,
        flow.flow_config_id
      ),
      envelope_alias
    ].compact.uniq
  end

  before do
    allow(flow).to receive(:resolve_additional_context_for).and_return(resolved_context)
  end

  it 'resolves additional context' do
    expect(flow.additional_context_resolver).to eq(resolver)
  end

  it 'adds an envelope for the derived category and the alias' do
    expect(additional_context.pluck('Category')).to match_array(expected_categories)
  end
end
