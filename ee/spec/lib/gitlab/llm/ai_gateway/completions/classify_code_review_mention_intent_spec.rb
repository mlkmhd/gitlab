# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Gitlab::Llm::AiGateway::Completions::ClassifyCodeReviewMentionIntent,
  feature_category: :code_suggestions do
  let_it_be(:user) { create(:user) }
  let_it_be(:project) { create(:project) }
  let_it_be(:merge_request) { create(:merge_request, source_project: project, target_project: project) }

  let(:prompt_message) do
    build(:ai_message, user: user, resource: merge_request, request_id: 'uuid',
      ai_action: 'classify_code_review_mention_intent')
  end

  let(:options) { { message: 'can you review this?' } }
  let(:intent_context) do
    {
      thread: '<message author="GitLabDuo">\nOne minor finding.\n</message>',
      thread_started_by_duo_review: true,
      duo_review_state: 'requested_changes'
    }
  end

  subject(:completion) { described_class.new(prompt_message, nil, options) }

  describe '#inputs' do
    it 'returns the message as inputs for the AI Gateway prompt' do
      expect(completion.inputs).to eq({ message: 'can you review this?' })
    end

    context 'with an intent context' do
      let(:options) { { message: 'please approve', intent_context: intent_context } }

      it 'adds the intent context to the inputs' do
        expect(completion.inputs).to eq({ message: 'please approve', **intent_context })
      end
    end
  end

  describe '#prompt_version' do
    it 'uses the default prompt version' do
      expect(completion.send(:prompt_version)).to be_nil
    end

    context 'with an intent context' do
      let(:options) { { message: 'please approve', intent_context: intent_context } }

      it 'uses the prompt version that reads the intent context' do
        expect(completion.send(:prompt_version)).to eq('^2.0.0')
      end
    end
  end

  describe '#unit_primitive_name' do
    it 'uses duo_agent_platform as the unit primitive' do
      expect(completion.send(:unit_primitive_name)).to eq(:duo_agent_platform)
    end
  end
end
