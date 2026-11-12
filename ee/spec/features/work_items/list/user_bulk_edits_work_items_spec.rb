# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'Work items bulk editing', :js, feature_category: :planning_views do
  include FilteredSearchHelpers
  include WorkItemsHelpers

  let_it_be(:user) { create(:user) }
  let_it_be(:group) { create(:group) }
  let_it_be(:project) { create(:project, group: group) }
  let_it_be(:bug_label) { create(:group_label, group: group, title: 'bug') }
  let_it_be(:epic) { create(:work_item, :epic, namespace: group, title: "Epic without label") }
  let_it_be(:issue) { create(:work_item, :issue, project: project, title: "Issue without label") }
  let_it_be(:issue_2) { create(:work_item, :issue, project: project, title: "Issue 2") }
  let_it_be(:incident) { create(:incident, project: project, title: "Incident 1") }
  let_it_be(:task) { create(:work_item, :task, project: project, title: "Task 1") }
  let_it_be(:objective) { create(:work_item, :objective, project: project, title: "Objective 1") }
  let_it_be(:shared_objective) { create(:work_item, :objective, project: project, title: "Objective 2") }
  let_it_be(:key_result) { create(:work_item, :key_result, project: project, title: "Key result 1") }

  before_all do
    group.add_developer(user)
  end

  before do
    sign_in user
    stub_licensed_features(epics: true, okrs: true, subepics: true)
    stub_feature_flags(okrs_mvc: true)
  end

  context 'when user is signed in' do
    context 'when bulk editing parent on group work items list' do
      before do
        allow(Gitlab::QueryLimiting).to receive(:threshold).and_return(132)
      end

      def visit_and_bulk_edit
        visit group_work_items_path(group)
        click_bulk_edit
      end

      it_behaves_like 'when user bulk assigns parent' do
        before do
          visit_and_bulk_edit
        end

        let(:child_work_item) { issue }
        let(:parent_work_item) { epic }
        let(:child_work_item_2) { issue_2 }
      end

      context 'when unassigning a parent' do
        before do
          create(:parent_link, work_item_parent: epic, work_item: issue)
          create(:parent_link, work_item_parent: epic, work_item: issue_2)

          visit_and_bulk_edit
        end

        it_behaves_like 'when user bulk unassigns parent' do
          let(:child_work_item) { issue }
          let(:parent_work_item) { epic }
          let(:child_work_item_2) { issue_2 }
        end
      end

      it_behaves_like 'when parent bulk edit shows no available items' do
        before do
          visit_and_bulk_edit
        end

        let(:incompatible_work_item) { incident }
        let(:incompatible_work_item_1) { issue }
        let(:incompatible_work_item_2) { task }
      end

      it_behaves_like 'when parent bulk edit fetches correct work items' do
        before do
          visit_and_bulk_edit
        end

        let(:child_work_item) { task }
        let(:parent_work_item) { issue }
        let(:incident_work_item) { incident }
      end

      it_behaves_like 'when user selects multiple types' do
        before do
          visit_and_bulk_edit
        end

        let(:compatible_work_item_type_1) { key_result }
        let(:compatible_work_item_type_2) { objective }
        let(:shared_parent_work_item) { shared_objective }
        let(:incompatible_work_item_type_1) { issue }
        let(:incompatible_work_item_type_2) { task }
      end
    end

    context 'when bulk editing parent on project work items list' do
      before do
        allow(Gitlab::QueryLimiting).to receive(:threshold).and_return(132)
      end

      def visit_and_bulk_edit
        visit project_work_items_path(project)
        # clear the type filter as we will also update task
        click_button 'Clear'
        # After clearing, the filtered search activates the last token which can
        # open the suggestion dropdown overlaying other elements. Blur the search
        # input and wait for the dropdown to close before proceeding.
        page.execute_script('document.activeElement.blur()')
        expect_hidden_suggestions_list
        click_bulk_edit
      end

      it_behaves_like 'when user bulk assigns parent' do
        before do
          visit_and_bulk_edit
        end

        let(:child_work_item) { issue }
        let(:parent_work_item) { epic }
        let(:child_work_item_2) { issue_2 }
      end

      context 'when unassigning a parent' do
        before do
          create(:parent_link, work_item_parent: epic, work_item: issue)
          create(:parent_link, work_item_parent: epic, work_item: issue_2)

          visit_and_bulk_edit
        end

        it_behaves_like 'when user bulk unassigns parent' do
          let(:child_work_item) { issue }
          let(:parent_work_item) { epic }
          let(:child_work_item_2) { issue_2 }
        end
      end

      it_behaves_like 'when parent bulk edit shows no available items' do
        before do
          visit_and_bulk_edit
        end

        let(:incompatible_work_item) { incident }
        let(:incompatible_work_item_1) { issue }
        let(:incompatible_work_item_2) { task }
      end

      it_behaves_like 'when parent bulk edit fetches correct work items' do
        before do
          visit_and_bulk_edit
        end

        let(:child_work_item) { task }
        let(:parent_work_item) { issue }
        let(:incident_work_item) { incident }
      end

      it_behaves_like 'when user selects multiple types' do
        before do
          visit_and_bulk_edit
        end

        let(:compatible_work_item_type_1) { key_result }
        let(:compatible_work_item_type_2) { objective }
        let(:shared_parent_work_item) { shared_objective }
        let(:incompatible_work_item_type_1) { issue }
        let(:incompatible_work_item_type_2) { task }
      end
    end

    context 'when bulk editing parent on epics list' do
      let_it_be(:child_epic_1) { create(:work_item, :epic, namespace: group, title: "Child epic 1") }
      let_it_be(:child_epic_2) { create(:work_item, :epic, namespace: group, title: "Child epic 2") }

      def visit_and_bulk_edit
        visit group_epics_path(group)
        click_bulk_edit
      end

      it_behaves_like 'when user bulk assigns parent' do
        before do
          visit_and_bulk_edit
        end

        let(:child_work_item) { child_epic_1 }
        let(:parent_work_item) { epic }
        let(:child_work_item_2) { child_epic_2 }
      end

      context 'when unassigning a parent' do
        before do
          create(:parent_link, work_item_parent: epic, work_item: child_epic_1)
          create(:parent_link, work_item_parent: epic, work_item: child_epic_2)

          visit_and_bulk_edit
        end

        it_behaves_like 'when user bulk unassigns parent' do
          let(:child_work_item) { child_epic_1 }
          let(:parent_work_item) { epic }
          let(:child_work_item_2) { child_epic_2 }
        end
      end
    end
  end
end
