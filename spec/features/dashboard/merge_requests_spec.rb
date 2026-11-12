# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'Dashboard Merge Requests', :with_current_organization, :js, feature_category: :code_review_workflow do
  include ListboxHelpers

  seed_internal_bot(:duo_code_review_bot)

  let(:current_user) { create(:user, organization: current_organization) }
  let(:user) { current_user }
  let(:project) { create(:project, organization: current_organization) }

  before do
    project.add_maintainer(current_user)
    sign_in(current_user)
  end

  describe 'sidebar' do
    it 'has nav items for assigned MRs and review requests' do
      visit merge_requests_dashboard_path

      within('#super-sidebar') do
        expect(page).to have_css("a[data-track-label='merge_requests_menu'][aria-current='page']")
      end
    end
  end

  context 'new merge request dropdown' do
    let(:project_with_disabled_merge_requests) { create(:project, :merge_requests_disabled) }

    before do
      create(:callout, user: user, feature_name: :merge_request_dashboard_display_preferences_popover)
      create(:callout, user: user, feature_name: :merge_request_dashboard_show_drafts)

      project_with_disabled_merge_requests.add_maintainer(current_user)
      visit merge_requests_dashboard_path
    end

    it 'shows projects only with merge requests feature enabled' do
      click_button 'Select project to create merge request'

      within_testid('new-resource-dropdown') do
        expect_listbox_item(project.full_name)
        expect_no_listbox_item(project_with_disabled_merge_requests.full_name)

        select_listbox_item(project.full_name)

        expect(page).to have_link("New merge request in #{project.name}")
      end
    end

    it 'passes axe automated accessibility testing' do
      expect(find('#content-body')).not_to have_content('Loading')

      expect(page).to be_axe_clean.within('#content-body')
    end
  end

  context 'search tab' do
    let(:author) { create(:user, organization: current_organization) }

    let!(:assigned_merge_request) do
      create(
        :merge_request,
        title: 'assigned_merge_request',
        assignees: [current_user],
        source_project: project,
        author: author
      )
    end

    let!(:other_merge_request) do
      create(
        :merge_request,
        title: 'other_merge_request',
        source_branch: 'fix',
        source_project: project,
        author: author
      )
    end

    it 'applies a filter from the query string' do
      visit merge_requests_search_dashboard_path(assignee_username: current_user.username)

      expect(page).to have_content(assigned_merge_request.title)
      expect(page).not_to have_content(other_merge_request.title)
    end
  end
end
