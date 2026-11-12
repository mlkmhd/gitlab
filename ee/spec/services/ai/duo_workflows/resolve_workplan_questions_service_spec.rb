# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Ai::DuoWorkflows::ResolveWorkplanQuestionsService, feature_category: :duo_agent_platform do
  let_it_be(:project) { create(:project) }
  let_it_be(:service_account) { create(:user, :service_account) }
  let_it_be(:developer) { create(:user, developer_of: project) }
  let_it_be(:work_item) { create(:work_item, project: project) }
  let_it_be(:workflow) do
    create(:duo_workflows_workflow, :input_required, work_item: work_item, project: project,
      workflow_definition: 'workplan/v1')
  end

  let(:current_user) { developer }

  subject(:result) { described_class.new(work_item: work_item, current_user: current_user).execute }

  def flow_note(type)
    note = create(type, noteable: work_item, project: project, author: service_account)
    create(:duo_workflows_workflow_note, workflow: workflow, note: note)
    note
  end

  def open_count
    Ai::DuoWorkflows::WorkplanQuestions.new(work_item, current_user).open_count
  end

  context 'when the flow posted a plain note' do
    let_it_be(:note) { flow_note(:note_on_work_item) }

    it 'converts it to a thread and resolves it', :aggregate_failures do
      expect { result }.to change { open_count }.from(1).to(0)

      expect(result).to be_success
      expect(Note.find(note.id)).to be_a(DiscussionNote)
      expect(Note.find(note.id)).to be_resolved
    end
  end

  context 'when the flow posted a discussion note' do
    let_it_be(:note) { flow_note(:discussion_note_on_work_item) }

    it 'resolves it', :aggregate_failures do
      expect { result }.to change { open_count }.from(1).to(0)
      expect(Note.find(note.id)).to be_resolved
    end
  end

  context 'when a thread is already resolved' do
    let_it_be(:note) { flow_note(:discussion_note_on_work_item) }

    before do
      note.discussion.resolve!(developer)
    end

    it 'leaves it untouched' do
      expect { result }.not_to change { Note.find(note.id).resolved_at }
    end
  end

  context 'when the note cannot be converted to a thread' do
    let_it_be(:note) { flow_note(:note_on_work_item) }

    before do
      allow_next_instance_of(IndividualNoteDiscussion) do |discussion|
        allow(discussion).to receive(:can_convert_to_discussion?).and_return(false)
      end
    end

    it 'resolves nothing', :aggregate_failures do
      expect { result }.not_to change { open_count }

      expect(result).to be_success
      expect(Note.find(note.id)).not_to be_a(DiscussionNote)
    end
  end

  context 'when the user cannot resolve notes' do
    let(:current_user) { create(:user) }
    let_it_be(:note) { flow_note(:note_on_work_item) }

    it 'resolves nothing', :aggregate_failures do
      expect { result }.not_to change { open_count }
      expect(Note.find(note.id)).not_to be_a(DiscussionNote)
    end
  end

  context 'when a note belongs to a human' do
    let_it_be(:note) { create(:note_on_work_item, noteable: work_item, project: project, author: developer) }

    it 'does not touch it', :aggregate_failures do
      result

      expect(Note.find(note.id)).not_to be_a(DiscussionNote)
      expect(Note.find(note.id)).not_to be_resolved
    end
  end

  context 'when saving fails' do
    let_it_be(:note) { flow_note(:note_on_work_item) }

    before do
      allow_next_found_instance_of(Note) { |n| allow(n).to receive(:save!).and_raise(ActiveRecord::RecordNotSaved) }
    end

    it 'returns an error' do
      expect(result).to be_error
    end
  end

  context 'when the feature flag is disabled' do
    let_it_be(:note) { flow_note(:discussion_note_on_work_item) }

    before do
      stub_feature_flags(workplan: false)
    end

    it 'returns an error and resolves nothing', :aggregate_failures do
      expect { result }.not_to change { open_count }

      expect(result).to be_error
      expect(result.reason).to eq(:feature_disabled)
    end
  end

  context 'when the feature flag is enabled for the project only' do
    let_it_be(:note) { flow_note(:discussion_note_on_work_item) }

    before do
      stub_feature_flags(workplan: project)
    end

    it 'returns an error and resolves nothing', :aggregate_failures do
      expect { result }.not_to change { open_count }

      expect(result).to be_error
      expect(result.reason).to eq(:feature_disabled)
    end
  end
end
