# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Gitlab::Duo::CodeReview::Mention::IntentContext, feature_category: :dap_code_review do
  let_it_be(:project) { create(:project, :repository) }
  let_it_be(:merge_request) { create(:merge_request, source_project: project, target_project: project) }
  let_it_be(:user) { create(:user, username: 'jane') }
  let_it_be(:review_bot) { ::Users::Internal.in_organization(project.organization_id).duo_code_review_bot }

  subject(:intent_context) { described_class.new(note, review_bot: review_bot).to_h }

  context 'when the note starts a thread' do
    let(:note) { create(:note, noteable: merge_request, project: project, author: user, note: '@GitLabDuo approve') }

    it 'returns no review context' do
      expect(intent_context).to eq(
        thread: '',
        thread_started_by_duo_review: false,
        duo_review_state: 'not_reviewer'
      )
    end
  end

  context 'when the note replies to a thread started by a Duo review' do
    let_it_be(:duo_note) do
      create(:discussion_note_on_merge_request, noteable: merge_request, project: project, author: review_bot,
        note: 'One minor finding.')
    end

    let(:note) do
      create(:discussion_note_on_merge_request, noteable: merge_request, project: project, author: user,
        discussion_id: duo_note.discussion_id, note: '@GitLabDuo MR description is now updated. Please approve.')
    end

    it 'returns the earlier notes of the thread, without the note itself' do
      expect(intent_context).to include(
        thread: "<message author=\"GitLabDuo\">\nOne minor finding.\n</message>",
        thread_started_by_duo_review: true
      )
    end

    it 'keeps only the last notes of the thread, truncated' do
      stub_const("#{described_class}::THREAD_NOTES_LIMIT", 1)
      stub_const("#{described_class}::NOTE_MAX_LENGTH", 10)
      create(:discussion_note_on_merge_request, noteable: merge_request, project: project, author: user,
        discussion_id: duo_note.discussion_id, note: 'A long reply from the author')

      expect(intent_context[:thread]).to eq("<message author=\"@jane\">\nA long ...\n</message>")
    end
  end

  context 'when Duo is a reviewer of the merge request' do
    let(:note) { create(:note, noteable: merge_request, project: project, author: user, note: '@GitLabDuo approve') }

    before do
      create(:merge_request_reviewer, merge_request: merge_request, reviewer: review_bot, state: :requested_changes)
    end

    it 'returns the Duo review state' do
      expect(intent_context[:duo_review_state]).to eq('requested_changes')
    end
  end

  context 'when the note is on an issue' do
    let_it_be(:issue) { create(:issue, project: project) }
    let(:note) { create(:note, noteable: issue, project: project, author: user, note: '@GitLabDuo approve') }

    it { is_expected.to include(duo_review_state: 'not_reviewer') }
  end
end
