# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Ai::DuoWorkflows::RunEvent, feature_category: :duo_agent_platform do
  let_it_be(:workflow) { create(:duo_workflows_workflow, :created) }

  subject(:event) { described_class.new(payload) }

  describe '#input?' do
    context 'with a symbol-keyed input' do
      let(:payload) { { type: :input, text: 'Fix the pipeline' } }

      it { expect(event.input?).to be(true) }
    end

    context 'with a string-keyed input' do
      let(:payload) { { 'type' => 'input', 'text' => 'Fix the pipeline' } }

      it { expect(event.input?).to be(true) }
    end

    context 'with blank text' do
      let(:payload) { { type: :input, text: '' } }

      it { expect(event.input?).to be(false) }
    end

    context 'with an extra key' do
      let(:payload) { { type: :input, text: 'Fix the pipeline', extra: true } }

      it { expect(event.input?).to be(false) }
    end

    context 'with the legacy goal type' do
      let(:payload) { { type: :goal, text: 'Fix the pipeline' } }

      it { expect(event.input?).to be(false) }
    end
  end

  describe '#approval?' do
    context 'with an approval' do
      let(:payload) { { type: :approval, approved: true } }

      it { expect(event.approval?).to be(true) }
    end

    context 'with a rejection message' do
      let(:payload) { { type: :approval, approved: false, message: 'No' } }

      it { expect(event.approval?).to be(true) }
    end

    context 'with a non-boolean decision' do
      let(:payload) { { type: :approval, approved: 'yes' } }

      it { expect(event.approval?).to be(false) }
    end

    context 'with a missing decision' do
      let(:payload) { { type: :approval, message: 'No' } }

      it { expect(event.approval?).to be(false) }
    end

    context 'with the legacy tool_approval type' do
      let(:payload) { { type: :tool_approval, approved: true } }

      it { expect(event.approval?).to be(false) }
    end
  end

  describe '#approval_with_message?' do
    using RSpec::Parameterized::TableSyntax

    where(:payload, :expected) do
      { type: :approval, approved: true, message: 'Looks good' } | true
      { type: :approval, approved: true, message: '' }           | false
      { type: :approval, approved: true }                        | false
      { type: :approval, approved: false, message: 'Not yet' }   | false
      { type: :input, text: 'Looks good' }                       | false
    end

    with_them do
      it { expect(event.approval_with_message?).to be(expected) }
    end
  end

  describe '#workhorse_approval' do
    context 'when approved' do
      let(:payload) { { type: :approval, approved: true } }

      it 'builds an empty approval' do
        expect(event.workhorse_approval).to eq({ 'approval' => {} })
      end
    end

    context 'when rejected' do
      let(:payload) { { type: :approval, approved: false, message: 'No' } }

      it 'builds a rejection with the message' do
        expect(event.workhorse_approval).to eq({ 'rejection' => { 'message' => 'No' } })
      end
    end
  end

  describe '#valid_for?' do
    context 'with a non-hash event' do
      let(:payload) { 'input' }

      it { expect(event.valid_for?(workflow)).to be(false) }
    end

    context 'with an input for a created session' do
      let(:payload) { { type: :input, text: 'Fix the pipeline' } }

      it { expect(event.valid_for?(workflow)).to be(true) }
    end

    context 'with an input for a session awaiting input' do
      let(:workflow) { create(:duo_workflows_workflow, :input_required) }
      let(:payload) { { type: :input, text: 'Please continue' } }

      it { expect(event.valid_for?(workflow)).to be(true) }
    end

    context 'with an input for a session awaiting an approval' do
      let(:workflow) { create(:duo_workflows_workflow, :tool_call_approval_required) }
      let(:payload) { { type: :input, text: 'Fix the pipeline' } }

      it { expect(event.valid_for?(workflow)).to be(false) }
    end

    context 'with an approval for a session awaiting a tool call approval' do
      let(:workflow) { create(:duo_workflows_workflow, :tool_call_approval_required) }
      let(:payload) { { type: :approval, approved: true } }

      it { expect(event.valid_for?(workflow)).to be(true) }
    end

    context 'with an approval for a session awaiting a plan approval' do
      let(:workflow) { create(:duo_workflows_workflow, :plan_approval_required) }
      let(:payload) { { type: :approval, approved: true } }

      it { expect(event.valid_for?(workflow)).to be(true) }
    end

    context 'with an approval for a session awaiting input' do
      let(:workflow) { create(:duo_workflows_workflow, :input_required) }
      let(:payload) { { type: :approval, approved: false, message: 'Not yet' } }

      it 'is valid, since an approval-type human_input gate pauses in input_required' do
        expect(event.valid_for?(workflow)).to be(true)
      end
    end

    context 'with an approval for a session that is not awaiting one' do
      let(:payload) { { type: :approval, approved: true } }

      it { expect(event.valid_for?(workflow)).to be(false) }
    end
  end

  describe '.for_resume' do
    using RSpec::Parameterized::TableSyntax

    let(:approved_reply) { described_class::APPROVED_REPLY }
    let(:rejected_reply) { described_class::REJECTED_REPLY }

    where(:trait, :definition, :approved, :message, :expected) do
      :tool_call_approval_required | 'developer/v1' | true  | nil | { type: :approval, approved: true }
      :tool_call_approval_required | 'chat'         | false | 'N' | { type: :approval, approved: false, message: 'N' }
      :input_required              | 'developer/v1' | false | 'N' | { type: :approval, approved: false, message: 'N' }
      :input_required              | 'developer/v1' | true  | nil | { type: :approval, approved: true }
      :input_required              | 'developer/v1' | false | nil | { type: :approval, approved: false }
      :input_required              | 'developer/v1' | true  | 'N' | { type: :approval, approved: true, message: 'N' }
      :input_required              | 'chat'         | false | 'N' | { type: :input, text: 'N' }
      :input_required              | 'chat'         | true  | nil | { type: :input, text: ref(:approved_reply) }
      :input_required              | 'chat'         | false | ''  | { type: :input, text: ref(:rejected_reply) }
    end

    with_them do
      let(:workflow) { build_stubbed(:duo_workflows_workflow, trait, workflow_definition: definition) }

      it 'builds the event for the pause, valid for the session', :aggregate_failures do
        resume = described_class.for_resume(workflow, approved: approved, message: message)

        expect(resume).to eq(expected)
        expect(described_class.new(resume).valid_for?(workflow)).to be(true)
      end
    end
  end
end
