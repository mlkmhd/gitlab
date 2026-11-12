# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'Issue Sidebar', :js, :saas, feature_category: :team_planning do
  let_it_be(:group) { create(:group_with_plan, :public, plan: :premium_plan) }
  let_it_be(:project) { create(:project, :public, namespace: group) }
  let_it_be(:user) { create(:user) }
  let_it_be(:label) { create(:label, project: project, title: 'bug') }
  let_it_be(:issue) { create(:labeled_issue, project: project, labels: [label]) }

  before do
    sign_in(user)
  end

  context 'for accessibility' do
    it 'passes axe automated accessibility testing' do
      project.add_developer(user)

      visit project_issue_path(project, issue)
      expect(page).to have_selector('section.work-item-overview-right-sidebar')

      expect(page).to be_axe_clean.within('section.work-item-overview-right-sidebar')
    end
  end
end
