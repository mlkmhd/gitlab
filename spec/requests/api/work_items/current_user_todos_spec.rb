# frozen_string_literal: true

require 'spec_helper'

RSpec.describe API::WorkItems::CurrentUserTodos, feature_category: :portfolio_management do
  let_it_be(:user) { create(:user) }
  let_it_be(:project) { create(:project, :private, reporters: user) }
  let_it_be(:work_item) { create(:work_item, :issue, project: project) }
  # Created with the work item: a note touches its noteable, which raises FrozenError once it is a minute old.
  let_it_be(:internal_note) { create(:note, :confidential, noteable: work_item, project: project) }

  let_it_be(:pending_todo) do
    create(:todo, :pending, user: user, project: project, target: work_item, target_type: 'WorkItem')
  end

  let_it_be(:done_todo) do
    create(:todo, :done, user: user, project: project, target: work_item, target_type: 'WorkItem')
  end

  before do
    stub_feature_flags(work_item_rest_api: true)
  end

  it_behaves_like 'work item list routes declaring cursor pagination', 'current_user_todos'

  shared_examples 'current_user_todos endpoint' do
    it 'returns the current user to-do items on the work item', :aggregate_failures do
      get api(api_request_path, user)

      expect(response).to have_gitlab_http_status(:ok)
      expect(json_response.pluck('id')).to contain_exactly(pending_todo.id, done_todo.id)
      expect(json_response).to all(include('id', 'state', 'target_type', 'action_name'))
    end

    it 'only returns to-do items belonging to the requesting user', :aggregate_failures do
      other_user = create(:user, reporter_of: project)
      create(:todo, :pending, user: other_user, project: project, target: work_item, target_type: 'WorkItem')

      get api(api_request_path, user)

      expect(response).to have_gitlab_http_status(:ok)
      expect(json_response.pluck('id')).to contain_exactly(pending_todo.id, done_todo.id)
    end

    context 'with a to-do on an internal note' do
      it 'returns the to-do to a user who can read internal notes' do
        internal_todo = create(:todo, :pending, user: user, project: project, target: work_item,
          target_type: 'WorkItem', note: internal_note)

        get api(api_request_path, user)

        expect(json_response.pluck('id')).to contain_exactly(pending_todo.id, done_todo.id, internal_todo.id)
      end

      it 'omits the to-do for a user who cannot read internal notes', :aggregate_failures do
        guest = create(:user, guest_of: project)
        visible_todo = create(:todo, :pending, user: guest, project: project, target: work_item,
          target_type: 'WorkItem')
        create(:todo, :pending, user: guest, project: project, target: work_item, target_type: 'WorkItem',
          note: internal_note)

        get api(api_request_path, guest)

        expect(response).to have_gitlab_http_status(:ok)
        expect(json_response.pluck('id')).to contain_exactly(visible_todo.id)
      end

      it 'returns an empty page with a next cursor when every record on it is unreadable', :aggregate_failures do
        guest = create(:user, guest_of: project)
        visible_todo = create(:todo, :pending, user: guest, project: project, target: work_item,
          target_type: 'WorkItem')
        create(:todo, :pending, user: guest, project: project, target: work_item, target_type: 'WorkItem',
          note: internal_note)

        get api(api_request_path, guest), params: { per_page: 1 }

        expect(response).to have_gitlab_http_status(:ok)
        expect(json_response).to eq([])
        expect(response.headers['Link']).to include('rel="next"')

        get api(api_request_path, guest), params: { per_page: 1, cursor: response.headers['X-Next-Cursor'] }

        expect(response).to have_gitlab_http_status(:ok)
        expect(json_response.pluck('id')).to eq([visible_todo.id])
        expect(response.headers['X-Next-Cursor']).to be_nil
      end
    end

    context 'with state filter' do
      it 'returns only pending to-do items when state=pending', :aggregate_failures do
        get api(api_request_path, user), params: { state: 'pending' }

        expect(response).to have_gitlab_http_status(:ok)
        expect(json_response.pluck('id')).to contain_exactly(pending_todo.id)
      end

      it 'returns only done to-do items when state=done', :aggregate_failures do
        get api(api_request_path, user), params: { state: 'done' }

        expect(response).to have_gitlab_http_status(:ok)
        expect(json_response.pluck('id')).to contain_exactly(done_todo.id)
      end

      it 'rejects an invalid state value' do
        get api(api_request_path, user), params: { state: 'invalid' }

        expect(response).to have_gitlab_http_status(:bad_request)
      end
    end

    it 'returns 404 when the work item does not exist' do
      get api(api_request_path.sub("/#{work_item.iid}/", "/#{non_existing_record_iid}/"), user)

      expect(response).to have_gitlab_http_status(:not_found)
    end

    it 'returns not_found when the feature flag is disabled' do
      stub_feature_flags(work_item_rest_api: false)

      get api(api_request_path, user)

      expect(response).to have_gitlab_http_status(:not_found)
    end

    it 'returns unauthorized when no token is provided' do
      get api(api_request_path)

      expect(response).to have_gitlab_http_status(:unauthorized)
    end

    it_behaves_like 'a work item endpoint paginated by cursor'

    it 'does not cause N+1 queries' do
      author = create(:user)
      create(:todo, :pending, user: user, project: project, target: work_item, target_type: 'WorkItem', author: author)

      control = ActiveRecord::QueryRecorder.new { get api(api_request_path, user) }

      new_author = create(:user)
      create(:todo, :pending, user: user, project: project, target: work_item, target_type: 'WorkItem',
        author: new_author)

      expect { get api(api_request_path, user) }.not_to exceed_query_limit(control)
    end
  end

  describe 'GET /projects/:id/-/work_items/:work_item_iid/current_user_todos' do
    let(:api_request_path) { "/projects/#{project.id}/-/work_items/#{work_item.iid}/current_user_todos" }

    it_behaves_like 'current_user_todos endpoint'

    it_behaves_like 'authorizing granular token permissions', :read_work_item do
      let(:boundary_object) { project }
      let(:request) do
        get api(api_request_path, personal_access_token: pat)
      end
    end

    it_behaves_like 'allows access with the ai_workflows scope' do
      let(:api_request) { get api(api_request_path, oauth_access_token: oauth_token) }

      it 'returns the todos' do
        api_request

        expect(json_response.pluck('id')).to contain_exactly(pending_todo.id, done_todo.id)
      end
    end

    it 'returns not_found when the user cannot read the work item' do
      other_user = create(:user)

      get api(api_request_path, other_user)

      expect(response).to have_gitlab_http_status(:not_found)
    end
  end

  describe 'GET /namespaces/:id/-/work_items/:work_item_iid/current_user_todos' do
    let(:api_request_path) do
      "/namespaces/#{CGI.escape(project.project_namespace.full_path)}/-/work_items/#{work_item.iid}/current_user_todos"
    end

    it_behaves_like 'current_user_todos endpoint'

    it_behaves_like 'authorizing granular token permissions', :read_work_item do
      let(:boundary_object) { project }
      let(:request) do
        get api(api_request_path, personal_access_token: pat)
      end
    end
  end
end
