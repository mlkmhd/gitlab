# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Gitlab::Suggestions::SuggestionSet, feature_category: :code_review_workflow do
  describe '#authors' do
    let_it_be(:project) { create(:project, :repository) }
    let_it_be(:merge_request) { create(:merge_request, source_project: project, target_project: project) }
    let_it_be(:user) { create(:user) }
    let_it_be(:service_account) { create(:service_account) }
    let_it_be(:workflow) do
      create(:duo_workflows_workflow, project: project, user: user, service_account: service_account)
    end

    def create_suggestion(author:, workflow: nil)
      note = create(:diff_note_on_merge_request, project: project, noteable: merge_request, author: author)
      create(:duo_workflows_workflow_note, workflow: workflow, note: note) if workflow

      create(:suggestion, note: note)
    end

    it 'credits a suggestion a flow wrote to the flow, whichever author the note stores' do
      stored_as_user = create_suggestion(author: user, workflow: workflow)
      stored_as_service_account = create_suggestion(author: service_account, workflow: workflow)

      expect(described_class.new([stored_as_user, stored_as_service_account]).authors)
        .to contain_exactly(service_account)
    end

    it 'credits a suggestion posted outside a session to the note author' do
      suggestion = create_suggestion(author: user)

      expect(described_class.new([suggestion]).authors).to contain_exactly(user)
    end
  end
end
