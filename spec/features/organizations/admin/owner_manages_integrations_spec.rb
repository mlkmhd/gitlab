# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'Organization owner manages integrations', :js, feature_category: :integrations do
  include JiraIntegrationHelpers

  include_context 'instance and group integration activation'

  let_it_be(:organization) { create(:organization) }
  let_it_be(:user) { create(:user, :organization_owner, organizations: [organization]) }

  before do
    stub_jira_integration_test
    sign_in(user)
  end

  it 'saves the integration as a default for the organization', :aggregate_failures do
    visit organization_admin_settings_integrations_path(organization)

    within('#content-body') do
      click_link('Jira issues', match: :prefer_exact)
    end

    fill_in 'Web URL', with: 'https://jira.example.com'
    fill_in 'Email or username', with: 'jira_user'
    fill_in 'API token or password', with: 'secret'
    click_save_integration

    expect(page).to have_text('Jira issues settings saved and active.')
    expect(page).to have_current_path(
      edit_organization_admin_settings_integration_path(organization, 'jira'), ignore_query: true
    )

    expect(Integrations::Jira.find_by(instance: true, organization: organization)).to have_attributes(
      url: 'https://jira.example.com',
      username: 'jira_user',
      password: 'secret'
    )
  end
end
