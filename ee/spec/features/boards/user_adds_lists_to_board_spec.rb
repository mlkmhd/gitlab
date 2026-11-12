# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'User adds custom status lists', :js, :aggregate_failures, feature_category: :planning_views do
  let_it_be(:group) { create(:group, :nested) }
  let_it_be(:root_group) { group.root_ancestor }
  let_it_be_with_reload(:project) { create(:project, :public, namespace: group) }
  let_it_be(:group_board) { create(:board, group: group) }
  let_it_be(:project_board) { create(:board, project: project) }
  let_it_be_with_reload(:user) { create(:user, maintainer_of: project, owner_of: group) }

  where(:board_type) do
    [[:project], [:group]]
  end

  with_them do
    context 'with custom statuses' do
      before do
        stub_licensed_features(
          board_milestone_lists: true,
          board_assignee_lists: true,
          board_iteration_lists: true,
          board_status_lists: true,
          work_item_status: true
        )
        sign_in(user)

        case board_type
        when :project
          visit project_board_path(project, project_board)
        when :group
          visit group_board_path(group, group_board)
        end

        wait_for_all_requests
      end

      let_it_be(:custom_status) do
        create(:work_item_custom_status, :to_do, name: "Custom to do", namespace: root_group)
      end

      let_it_be(:custom_lifecycle) do
        create(:work_item_custom_lifecycle, default_open_status: custom_status, namespace: root_group)
      end

      let!(:type_custom_lifecycle) do
        create(:work_item_type_custom_lifecycle,
          lifecycle: custom_lifecycle,
          work_item_type: build(:work_item_system_defined_type, :issue),
          namespace: root_group
        )
      end

      # Created after the lifecycle connection so the status row passes validation and is persisted.
      let!(:issue_with_custom_status) do
        create(:work_item, project: project, custom_status_id: custom_status.id)
      end

      it 'creates status column for custom status' do
        type_custom_lifecycle

        page.refresh

        add_list('Status', custom_status.name)

        expect(page).to have_selector('.board', text: custom_status.name)
        expect(find('[data-testid="board-list"]:nth-child(2)')).to have_content(issue_with_custom_status.title)
      end
    end
  end

  def add_list(list_type, title)
    click_button 'New list'
    wait_for_all_requests

    page.choose(list_type)

    find_button("Select a").click

    within_testid('base-dropdown-menu') do
      find('label', text: title).click
    end

    click_button 'Add to board'

    wait_for_all_requests
  end
end
