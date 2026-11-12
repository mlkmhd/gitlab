# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'Abuse reports', :js, feature_category: :insider_threat do
  let_it_be(:abusive_user) { create(:user) }

  let_it_be(:reporter1) { create(:user) }

  let_it_be(:project) { create(:project, :public, :repository) }
  let_it_be(:issue) { create(:issue, project: project, author: abusive_user) }

  before do
    stub_feature_flags(hide_incident_management_features: false)

    sign_in(reporter1)
  end

  describe 'report abuse to administrator' do
    shared_examples 'cancel report' do
      it 'redirects backs to user profile when cancel button is clicked' do
        fill_and_submit_abuse_category_form

        click_link 'Cancel'

        expect(page).to have_current_path(user_path(abusive_user))
      end
    end

    context 'when reporting an issue for abuse' do
      before do
        visit project_issue_path(project, issue)

        click_button 'More actions', match: :first
      end

      it 'redirects backs to the issue when cancel button is clicked' do
        fill_and_submit_abuse_category_form

        click_link 'Cancel'

        expect(page).to have_current_path(project_work_item_path(project, issue.iid))
      end
    end

    context 'when reporting an incident for abuse' do
      let_it_be(:incident) { create(:incident, project: project, author: abusive_user) }

      before do
        visit incident_project_issues_path(project, incident)

        within_testid('issue-header') do
          find_by_testid('desktop-dropdown').click
        end
      end

      it_behaves_like 'reports the user with an abuse category'
    end

    context 'when reporting a user profile for abuse' do
      before do
        visit user_path(abusive_user)
        find_by_testid('user-profile-actions').click
      end

      it_behaves_like 'reports the user with an abuse category'

      it_behaves_like 'cancel report'
    end

    context 'when reporting an merge request for abuse' do
      let_it_be(:merge_request) { create(:merge_request, source_project: project, author: abusive_user) }

      before do
        visit project_merge_request_path(project, merge_request)
        find_by_testid('merge-request-actions').click
      end

      it_behaves_like 'reports the user with an abuse category'
    end
  end

  private

  def fill_and_submit_abuse_category_form
    click_button 'Report abuse'

    choose "They're posting spam or unsolicited content."
    click_button 'Next'
  end
end
