# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Gitlab::Duo::CodeReview::Mention::ConversationThread, feature_category: :dap_code_review do
  let_it_be(:project) { create(:project, :repository) }
  let_it_be(:merge_request) { create(:merge_request, source_project: project, target_project: project) }
  let_it_be(:user) { create(:user, username: 'jane') }
  let_it_be(:review_bot) { ::Users::Internal.in_organization(project.organization_id).duo_code_review_bot }

  let_it_be(:duo_note) do
    create(:discussion_note_on_merge_request, noteable: merge_request, project: project, author: review_bot,
      note: 'One minor finding.')
  end

  let_it_be(:reply) do
    create(:discussion_note_on_merge_request, noteable: merge_request, project: project, author: user,
      discussion_id: duo_note.discussion_id, note: 'This does not apply here.')
  end

  let_it_be(:note) do
    create(:discussion_note_on_merge_request, noteable: merge_request, project: project, author: user,
      discussion_id: duo_note.discussion_id, note: '@GitLabDuo please approve')
  end

  let(:options) { {} }

  subject(:conversation_thread) { described_class.new(note, **options) }

  describe '#notes' do
    it 'returns all the notes of the discussion, oldest first' do
      expect(conversation_thread.notes).to eq([duo_note, reply, note])
    end
  end

  describe '#messages' do
    it 'renders all the notes of the discussion, including the note itself' do
      expect(conversation_thread.messages).to eq([
        "<message author=\"GitLabDuo\">\nOne minor finding.\n</message>",
        "<message author=\"@jane\">\nThis does not apply here.\n</message>",
        "<message author=\"@jane\">\n@GitLabDuo please approve\n</message>"
      ])
    end

    context 'when include_current is false' do
      let(:options) { { include_current: false } }

      it 'renders only the earlier notes' do
        expect(conversation_thread.messages).to eq([
          "<message author=\"GitLabDuo\">\nOne minor finding.\n</message>",
          "<message author=\"@jane\">\nThis does not apply here.\n</message>"
        ])
      end
    end

    context 'with a limit' do
      let(:options) { { include_current: false, limit: 1 } }

      it 'renders only the last notes' do
        expect(conversation_thread.messages)
          .to eq(["<message author=\"@jane\">\nThis does not apply here.\n</message>"])
      end
    end

    context 'with max_length' do
      let(:options) { { max_length: 10 } }

      it 'truncates each note body' do
        expect(conversation_thread.messages.first).to eq("<message author=\"GitLabDuo\">\nOne min...\n</message>")
      end
    end

    it 'preloads the authors of the notes' do
      conversation_thread.notes

      expect { conversation_thread.messages }.not_to exceed_query_limit(1)
    end
  end
end
