# frozen_string_literal: true

require 'spec_helper'

# The sidebar widgets are covered by the integration specs in
# ee/spec/frontend/integration/work_items/details/ (assignees, labels, milestone) and by
# describeDrawerInteractions in ee/spec/frontend/integration/work_items/drawer_shared_test_helpers.js.
# What stays here needs the real backend: inviting members, and a due date surviving a reload.
RSpec.describe 'Issue Sidebar', :js, feature_category: :team_planning do
  include Features::InviteMembersModalHelpers
  let_it_be(:group) { create(:group, :nested) }
  let_it_be(:project) { create(:project, :public, namespace: group) }
  let_it_be(:user) { create(:user) }
  let_it_be(:issue) { create(:issue, project: project) }

  before do
    stub_incoming_email_setting(enabled: true, address: "p+%{key}@gl.ab")
  end

  context 'when signed in' do
    before do
      sign_in(user)
    end

    context 'for assignee widget' do
      let(:user2) { create(:user) }
      let(:issue2) { create(:issue, project: project, author: user2) }

      include_examples 'issuable invite members' do
        let(:issuable_path) { project_issue_path(project, issue2) }
      end
    end

    context 'as an allowed user' do
      before do
        project.add_developer(user)
        visit project_issue_path(project, issue)
      end

      context 'for dates widget' do
        it 'ensures the due date is persisted after a reload', :sidekiq_inline do
          # Issues with empty dates sources were not persisting the due date on edit
          # https://gitlab.com/gitlab-org/gitlab/-/issues/517311
          create(:work_items_dates_source, issue_id: issue.id)

          new_date = Time.zone.today

          wait_for_all_requests

          within_testid('work-item-due-dates') do
            click_button 'Edit'
            find_field('Due').click
          end
          within('.pika-lendar') do
            click_button new_date.day.to_s
          end
          within_testid('work-item-due-dates') do
            click_button 'Apply'

            expect(page).to have_text(new_date.strftime('%b %-d, %Y'))
          end

          visit project_issue_path(project, issue)

          within_testid('work-item-due-dates') do
            expect(page).to have_text(new_date.strftime('%b %-d, %Y'))
          end
        end
      end
    end
  end

  def open_assignees_dropdown
    within_testid('work-item-assignees') do
      click_button('Edit')
    end
  end
end
