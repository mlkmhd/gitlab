# frozen_string_literal: true

require 'spec_helper'

RSpec.describe API::WorkItems::CurrentUserTodos, feature_category: :portfolio_management do
  let_it_be(:user) { create(:user) }
  let_it_be(:group) { create(:group, :private, reporters: user) }
  let_it_be(:epic) { create(:work_item, :epic, namespace: group, author: user) }
  # Created with the epic: a note touches its noteable, which raises FrozenError once it is a minute old.
  let_it_be(:internal_note) { create(:note, :confidential, noteable: epic, project: nil, namespace: group) }

  let_it_be(:todo) do
    create(:todo, :pending, user: user, group: group, target: epic, target_type: 'WorkItem')
  end

  before do
    stub_licensed_features(epics: true)
  end

  describe 'GET /groups/:id/-/work_items/:work_item_iid/current_user_todos' do
    let(:api_request_path) { "/groups/#{group.id}/-/work_items/#{epic.iid}/current_user_todos" }

    it 'returns the current user to-do items on the group-level work item', :aggregate_failures do
      get api(api_request_path, user)

      expect(response).to have_gitlab_http_status(:ok)
      expect(json_response.pluck('id')).to contain_exactly(todo.id)
    end

    context 'with a to-do on an internal note' do
      it 'returns the to-do to a user who can read internal notes' do
        internal_todo = create(:todo, :pending, user: user, group: group, target: epic, target_type: 'WorkItem',
          note: internal_note)

        get api(api_request_path, user)

        expect(json_response.pluck('id')).to contain_exactly(todo.id, internal_todo.id)
      end

      # Group-level to-dos are never cleaned up when the user loses access, so the endpoint must filter them.
      it 'omits the to-do for a user who cannot read internal notes', :aggregate_failures do
        guest = create(:user, guest_of: group)
        visible_todo = create(:todo, :pending, user: guest, group: group, target: epic, target_type: 'WorkItem')
        create(:todo, :pending, user: guest, group: group, target: epic, target_type: 'WorkItem', note: internal_note)

        get api(api_request_path, guest)

        expect(response).to have_gitlab_http_status(:ok)
        expect(json_response.pluck('id')).to contain_exactly(visible_todo.id)
      end
    end

    it_behaves_like 'authorizing granular token permissions', :read_work_item do
      let(:boundary_object) { group }
      let(:request) do
        get api(api_request_path, personal_access_token: pat)
      end
    end

    context 'without the epics license' do
      before do
        stub_licensed_features(epics: false)
      end

      it 'returns 404 when the parent is not readable' do
        get api(api_request_path, user)

        expect(response).to have_gitlab_http_status(:not_found)
      end
    end
  end
end
