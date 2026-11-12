# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Ai::Catalog::FoundationalFlow::CodeReview::Context, feature_category: :dap_code_review do
  describe '.call' do
    subject(:context) do
      described_class.call(
        runtime_context: Ai::DuoWorkflows::AdditionalContext::RuntimeContext.new(
          project: nil, resource: resource, goal: nil, primary_branch: nil
        )
      )
    end

    let_it_be(:merge_request) { create(:merge_request) }

    let(:review_bot) do
      ::Users::Internal.in_organization(merge_request.project.organization_id).duo_code_review_bot
    end

    context 'when the resource is not a merge request' do
      let(:resource) { build_stubbed(:issue) }

      it 'resolves to no context without looking the bot up' do
        expect(::Users::Internal).not_to receive(:in_organization)

        expect(context).to eq({})
      end
    end

    context 'when the resource is a merge request' do
      let(:resource) { merge_request }

      context 'when the bot reviewed the merge request before' do
        before do
          create(
            :diff_note_on_merge_request,
            noteable: merge_request, project: merge_request.project, author: review_bot,
            review: create(:review, merge_request: merge_request, project: merge_request.project, author: review_bot)
          )
        end

        it 'returns the username of the Duo Code Review bot and the last reviewed head sha' do
          expect(context).to eq(
            "duo_code_review_bot_name" => review_bot.username,
            "last_reviewed_head_sha" => merge_request.diff_refs.head_sha
          )
        end
      end

      context 'when the bot did not review the merge request before' do
        it 'omits the last reviewed head sha' do
          expect(context).to eq("duo_code_review_bot_name" => review_bot.username)
        end
      end
    end
  end
end
