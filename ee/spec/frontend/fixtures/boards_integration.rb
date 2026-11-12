# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'Boards list management Integration (GraphQL fixtures)', type: :request,
  feature_category: :planning_views do
  include ApiHelpers
  include GraphqlHelpers
  include JavaScriptFixturesHelpers

  let_it_be(:group) { create(:group, :nested, :public) }
  let_it_be(:project) { create(:project, :public, namespace: group) }
  let_it_be(:group_board) { create(:board, group: group) }
  let_it_be(:project_board) { create(:board, project: project) }
  let_it_be(:user) do
    create(:user, name: 'Board Owner', username: 'board-owner', maintainer_of: project, owner_of: group)
  end

  let_it_be(:group_label) { create(:group_label, group: group, title: 'Frontend') }
  let_it_be(:group_label_2) { create(:group_label, group: group, title: 'Backend') }
  let_it_be(:project_label) { create(:label, project: project, title: 'Bug') }

  let_it_be(:issue) { create(:labeled_issue, project: project, title: 'Labeled issue', labels: [group_label]) }

  let_it_be(:milestone) { create(:milestone, group: group, title: '16.0') }
  let_it_be(:iterations_cadence) { create(:iterations_cadence, group: group, title: 'Sprint Cadence') }
  let_it_be(:iteration) do
    create(:iteration, :with_title, title: 'Sprint 1', iterations_cadence: iterations_cadence)
  end

  let_it_be(:system_defined_status) { build(:work_item_system_defined_status, :to_do) }

  before do
    stub_licensed_features(
      board_milestone_lists: true,
      board_assignee_lists: true,
      board_iteration_lists: true,
      board_status_lists: true,
      work_item_status: true
    )
  end

  base_output_path = 'graphql/boards/integration/'

  def project_board_query
    get_graphql_query_as_string('boards/graphql/project_board.query.graphql')
  end

  def group_board_query
    get_graphql_query_as_string('boards/graphql/group_board.query.graphql')
  end

  def list_issues_query
    get_graphql_query_as_string('boards/graphql/board_lists.query.graphql', ee: true)
  end

  def lists_issues_query
    get_graphql_query_as_string('boards/graphql/lists_issues.query.graphql')
  end

  def board_labels_query
    get_graphql_query_as_string('boards/graphql/board_labels.query.graphql')
  end

  def project_board_milestones_query
    get_graphql_query_as_string('boards/graphql/project_board_milestones.query.graphql')
  end

  def group_board_milestones_query
    get_graphql_query_as_string('boards/graphql/group_board_milestones.query.graphql')
  end

  def users_autocomplete_query
    get_graphql_query_as_string('graphql_shared/queries/users_autocomplete.query.graphql')
  end

  def search_iterations_query
    get_graphql_query_as_string('work_items/list/graphql/search_iterations.query.graphql', ee: true)
  end

  def create_list_mutation
    get_graphql_query_as_string('boards/graphql/board_list_create.mutation.graphql', ee: true)
  end

  describe GraphQL::Query, 'board metadata' do
    it "#{base_output_path}project_board.query.graphql.json" do
      post_graphql(project_board_query, current_user: user,
        variables: { fullPath: project.full_path, boardId: project_board.to_global_id.to_s })

      expect_graphql_errors_to_be_empty
    end

    it "#{base_output_path}group_board.query.graphql.json" do
      post_graphql(group_board_query, current_user: user,
        variables: { fullPath: group.full_path, boardId: group_board.to_global_id.to_s })

      expect_graphql_errors_to_be_empty
    end
  end

  describe GraphQL::Query, 'lists' do
    it "#{base_output_path}list_issues_project.query.graphql.json" do
      post_graphql(list_issues_query, current_user: user,
        variables: {
          fullPath: project.full_path, boardId: project_board.to_global_id.to_s,
          isGroup: false, isProject: true
        })

      expect_graphql_errors_to_be_empty
    end

    it "#{base_output_path}list_issues_group.query.graphql.json" do
      post_graphql(list_issues_query, current_user: user,
        variables: {
          fullPath: group.full_path, boardId: group_board.to_global_id.to_s,
          isGroup: true, isProject: false
        })

      expect_graphql_errors_to_be_empty
    end
  end

  describe GraphQL::Query, 'lists issues' do
    let_it_be(:project_label_list) { create(:list, board: project_board, label: group_label, position: 1) }
    let_it_be(:project_empty_list) { create(:list, board: project_board, label: project_label, position: 2) }

    it "#{base_output_path}lists_issues_with_issue.query.graphql.json" do
      post_graphql(lists_issues_query, current_user: user,
        variables: {
          fullPath: project.full_path, boardId: project_board.to_global_id.to_s,
          id: project_label_list.to_global_id.to_s, isGroup: false, isProject: true, first: 20
        })

      expect_graphql_errors_to_be_empty
      expect(graphql_dig_at(graphql_data, :project, :board, :lists, :nodes, 0, :issues, :nodes)).not_to be_empty
    end

    it "#{base_output_path}lists_issues_empty.query.graphql.json" do
      post_graphql(lists_issues_query, current_user: user,
        variables: {
          fullPath: project.full_path, boardId: project_board.to_global_id.to_s,
          id: project_empty_list.to_global_id.to_s, isGroup: false, isProject: true, first: 20
        })

      expect_graphql_errors_to_be_empty
      expect(graphql_dig_at(graphql_data, :project, :board, :lists, :nodes, 0, :issues, :nodes)).to be_empty
    end
  end

  describe GraphQL::Query, 'labels' do
    it "#{base_output_path}board_labels_project.query.graphql.json" do
      post_graphql(board_labels_query, current_user: user,
        variables: { fullPath: project.full_path, searchTerm: '', isGroup: false, isProject: true })

      expect_graphql_errors_to_be_empty
    end

    it "#{base_output_path}board_labels_group.query.graphql.json" do
      post_graphql(board_labels_query, current_user: user,
        variables: { fullPath: group.full_path, searchTerm: '', isGroup: true, isProject: false })

      expect_graphql_errors_to_be_empty
    end
  end

  describe GraphQL::Query, 'milestones' do
    it "#{base_output_path}project_board_milestones.query.graphql.json" do
      post_graphql(project_board_milestones_query, current_user: user,
        variables: { fullPath: project.full_path, searchTerm: '' })

      expect_graphql_errors_to_be_empty
    end

    it "#{base_output_path}group_board_milestones.query.graphql.json" do
      post_graphql(group_board_milestones_query, current_user: user,
        variables: { fullPath: group.full_path, searchTerm: '' })

      expect_graphql_errors_to_be_empty
    end
  end

  describe GraphQL::Query, 'assignees' do
    it "#{base_output_path}users_autocomplete_project.query.graphql.json" do
      post_graphql(users_autocomplete_query, current_user: user,
        variables: { fullPath: project.full_path, search: '', isProject: true })

      expect_graphql_errors_to_be_empty
    end

    it "#{base_output_path}users_autocomplete_group.query.graphql.json" do
      post_graphql(users_autocomplete_query, current_user: user,
        variables: { fullPath: group.full_path, search: '', isProject: false })

      expect_graphql_errors_to_be_empty
    end
  end

  describe GraphQL::Query, 'iterations' do
    it "#{base_output_path}search_iterations_project.query.graphql.json" do
      post_graphql(search_iterations_query, current_user: user,
        variables: { fullPath: project.full_path, search: '', isProject: true })

      expect_graphql_errors_to_be_empty
    end

    it "#{base_output_path}search_iterations_group.query.graphql.json" do
      post_graphql(search_iterations_query, current_user: user,
        variables: { fullPath: group.full_path, search: '', isProject: false })

      expect_graphql_errors_to_be_empty
    end
  end

  describe GraphQL::Query, 'create list mutation' do
    it "#{base_output_path}board_list_create_label.mutation.graphql.json" do
      post_graphql(create_list_mutation, current_user: user,
        variables: { boardId: project_board.to_global_id.to_s, labelId: group_label.to_global_id.to_s,
                     position: nil })

      expect_graphql_errors_to_be_empty
    end

    it "#{base_output_path}board_list_create_milestone.mutation.graphql.json" do
      post_graphql(create_list_mutation, current_user: user,
        variables: { boardId: project_board.to_global_id.to_s, milestoneId: milestone.to_global_id.to_s,
                     position: nil })

      expect_graphql_errors_to_be_empty
    end

    it "#{base_output_path}board_list_create_assignee.mutation.graphql.json" do
      post_graphql(create_list_mutation, current_user: user,
        variables: { boardId: project_board.to_global_id.to_s, assigneeId: user.to_global_id.to_s,
                     position: nil })

      expect_graphql_errors_to_be_empty
    end

    it "#{base_output_path}board_list_create_iteration.mutation.graphql.json" do
      post_graphql(create_list_mutation, current_user: user,
        variables: { boardId: project_board.to_global_id.to_s, iterationId: iteration.to_global_id.to_s,
                     position: nil })

      expect_graphql_errors_to_be_empty
    end

    it "#{base_output_path}board_list_create_status.mutation.graphql.json" do
      post_graphql(create_list_mutation, current_user: user,
        variables: { boardId: project_board.to_global_id.to_s,
                     statusId: system_defined_status.to_global_id.to_s, position: nil })

      expect_graphql_errors_to_be_empty
    end
  end
end
