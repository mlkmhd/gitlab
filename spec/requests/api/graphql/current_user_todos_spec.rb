# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'A Todoable that implements the CurrentUserTodos interface',
  feature_category: :notifications do
  include GraphqlHelpers

  let_it_be(:current_user) { create(:user) }
  let_it_be(:project) { create(:project, :public) }
  let_it_be(:todoable) { create(:issue, project: project) }
  let_it_be(:done_todo) { create(:todo, state: :done, target: todoable, user: current_user) }
  let_it_be(:pending_todo) { create(:todo, state: :pending, target: todoable, user: current_user) }

  let(:state) { 'null' }

  let(:todoable_response) do
    graphql_data_at(:project, :issue, :currentUserTodos, :nodes)
  end

  let(:query) do
    <<~GQL
      {
        project(fullPath: "#{project.full_path}") {
          issue(iid: "#{todoable.iid}") {
            currentUserTodos(state: #{state}) {
              nodes {
                #{all_graphql_fields_for('Todo', max_depth: 1)}
              }
            }
          }
        }
      }
    GQL
  end

  it 'returns todos of the current user' do
    post_graphql(query, current_user: current_user)

    expect(todoable_response).to contain_exactly(
      a_graphql_entity_for(done_todo),
      a_graphql_entity_for(pending_todo)
    )
  end

  it 'does not return todos of another user', :aggregate_failures do
    post_graphql(query, current_user: create(:user))

    expect(response).to have_gitlab_http_status(:success)
    expect(todoable_response).to be_empty
  end

  it 'does not error when there is no logged in user', :aggregate_failures do
    post_graphql(query)

    expect(response).to have_gitlab_http_status(:success)
    expect(todoable_response).to be_empty
  end

  context 'when `state` argument is `pending`' do
    let(:state) { 'pending' }

    it 'returns just the pending todo' do
      post_graphql(query, current_user: current_user)

      expect(todoable_response).to contain_exactly(
        a_graphql_entity_for(pending_todo)
      )
    end
  end

  context 'when to-do items were created from notes' do
    let(:state) { 'pending' }

    let(:query) do
      <<~GQL
        {
          project(fullPath: "#{project.full_path}") {
            issue(iid: "#{todoable.iid}") {
              currentUserTodos(state: #{state}) {
                nodes {
                  id
                  note {
                    id
                  }
                }
              }
            }
          }
        }
      GQL
    end

    def create_note_todos(count)
      Array.new(count) do
        note = create(:note, project: project, noteable: todoable, author: current_user)
        create(:todo, state: :pending, target: todoable, note: note, user: current_user, project: project)
      end
    end

    it 'does not run more queries as the number of to-do items grows' do
      create_note_todos(2)
      post_graphql(query, current_user: current_user)

      control = ActiveRecord::QueryRecorder.new(skip_cached: false) do
        post_graphql(query, current_user: current_user)
      end

      create_note_todos(3)

      expect { post_graphql(query, current_user: current_user) }.not_to exceed_all_query_limit(control)
      expect(todoable_response.pluck('note').compact.size).to eq(5)
    end
  end

  context 'when to-do items were created from notes on many issues' do
    let_it_be(:group) { create(:group, :public) }

    let(:query) do
      <<~GQL
        {
          group(fullPath: "#{group.full_path}") {
            issues(includeSubgroups: true) {
              nodes {
                currentUserTodos(state: pending) {
                  nodes {
                    id
                    note {
                      id
                    }
                  }
                }
              }
            }
          }
        }
      GQL
    end

    def create_issue_with_note_todo
      issue_project = create(:project, :public, group: group)
      issue = create(:issue, project: issue_project)
      note = create(:note, project: issue_project, noteable: issue, author: current_user)
      create(:todo, state: :pending, target: issue, note: note, user: current_user, project: issue_project)
    end

    it 'does not run more queries as the number of issues grows' do
      create_issue_with_note_todo
      create_issue_with_note_todo
      post_graphql(query, current_user: current_user)

      control = ActiveRecord::QueryRecorder.new(skip_cached: false) do
        post_graphql(query, current_user: current_user)
      end

      create_issue_with_note_todo
      create_issue_with_note_todo

      expect { post_graphql(query, current_user: current_user) }.not_to exceed_all_query_limit(control)

      notes = graphql_data_at(:group, :issues, :nodes, :currentUserTodos, :nodes, :note)
      expect(notes.compact.size).to eq(4)
    end
  end

  context 'when to-do items were created from notes on many merge requests' do
    let_it_be(:group) { create(:group, :public) }

    let(:query) do
      <<~GQL
        {
          group(fullPath: "#{group.full_path}") {
            mergeRequests(includeSubgroups: true) {
              nodes {
                currentUserTodos(state: pending) {
                  nodes {
                    id
                    note {
                      id
                    }
                  }
                }
              }
            }
          }
        }
      GQL
    end

    def create_merge_request_with_note_todo
      mr_project = create(:project, :public, :repository, group: group)
      merge_request = create(:merge_request, source_project: mr_project)
      note = create(:note, project: mr_project, noteable: merge_request, author: current_user)
      create(:todo, state: :pending, target: merge_request, note: note, user: current_user, project: mr_project)
    end

    it 'does not run more queries as the number of merge requests grows' do
      create_merge_request_with_note_todo
      create_merge_request_with_note_todo
      post_graphql(query, current_user: current_user)

      control = ActiveRecord::QueryRecorder.new(skip_cached: false) do
        post_graphql(query, current_user: current_user)
      end

      create_merge_request_with_note_todo
      create_merge_request_with_note_todo

      expect { post_graphql(query, current_user: current_user) }.not_to exceed_all_query_limit(control)

      notes = graphql_data_at(:group, :merge_requests, :nodes, :currentUserTodos, :nodes, :note)
      expect(notes.compact.size).to eq(4)
    end
  end

  context 'when `state` argument is `done`' do
    let(:state) { 'done' }

    it 'returns just the done todo' do
      post_graphql(query, current_user: current_user)

      expect(todoable_response).to contain_exactly(
        a_graphql_entity_for(done_todo)
      )
    end
  end
end
