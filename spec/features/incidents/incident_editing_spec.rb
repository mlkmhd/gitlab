# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'editing an incident through the legacy issuable app', :js, feature_category: :incident_management do
  let_it_be(:project, freeze: false) { create(:project) }
  let_it_be(:developer) { create(:user, developer_of: project) }
  let_it_be_with_reload(:incident) do
    create(:incident, project: project, author: developer, title: 'Old title', description: 'desc')
  end

  before do
    stub_feature_flags(hide_incident_management_features: false)
    sign_in(developer)
    visit incident_project_issues_path(project, incident)
  end

  it 'saves a new title' do
    expect(page).to have_css('h1', text: 'Old title')

    click_button 'Edit title and description'

    within_testid('issuable-form') do
      fill_in 'Title', with: 'New title'
      click_button 'Save changes'
    end

    expect(page).to have_css('h1', text: 'New title')
    expect(incident.reload.title).to eq('New title')
  end
end
