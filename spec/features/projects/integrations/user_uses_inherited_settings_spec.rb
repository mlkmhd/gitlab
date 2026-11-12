# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'User uses inherited settings', :js, feature_category: :integrations do
  include JiraIntegrationHelpers
  include ListboxHelpers

  include_context 'project integration activation'

  before do
    stub_jira_integration_test
  end

  shared_examples 'inherited settings' do
    let_it_be(:project_settings) { { url: 'http://project.com', password: 'project' } }

    describe 'switching from inherited to custom settings' do
      let_it_be(:integration) { create(:jira_integration, project: project, inherit_from_id: parent_integration.id, **project_settings) }

      it 'clears the form fields and saves the entered values' do
        visit_project_integration('Jira')

        expect(page).not_to have_button('Use custom settings')
        expect(page).to have_text(parent_description)
        expect(page).to have_field('Web URL', with: parent_settings[:url], readonly: true)
        expect(page).to have_field('New API token or password', with: '', readonly: true)

        select_from_listbox('Use custom settings', from: 'Use default settings')

        expect(page).not_to have_button('Use default settings')
        expect(page).to have_field('Web URL', with: project_settings[:url], readonly: false)
        expect(page).to have_field('New API token or password', with: '', readonly: false)

        fill_in 'Web URL', with: 'http://custom.com'
        fill_in 'New API token or password', with: 'custom'

        click_save_integration

        expect(page).to have_text('Jira issues settings saved and active.')
        expect(integration.reload).to have_attributes(
          inherit_from_id: nil,
          url: 'http://custom.com',
          password: 'custom'
        )
      end
    end

    describe 'switching from custom to inherited settings' do
      let_it_be(:integration) { create(:jira_integration, project: project, **project_settings) }

      it 'resets the form fields, makes them read-only, and saves the inherited values' do
        visit_project_integration('Jira')

        expect(page).not_to have_button('Use default settings')
        expect(page).to have_field('URL', with: project_settings[:url], readonly: false)
        expect(page).to have_field('New API token or password', with: '', readonly: false)

        select_from_listbox('Use default settings', from: 'Use custom settings')

        expect(page).not_to have_button('Use custom settings')
        expect(page).to have_field('URL', with: parent_settings[:url], readonly: true)
        expect(page).to have_field('New API token or password', with: '', readonly: true)

        click_save_integration

        expect(page).to have_text('Jira issues settings saved and active.')
        expect(integration.reload).to have_attributes(
          inherit_from_id: parent_integration.id,
          **parent_settings
        )
      end
    end
  end

  context 'with organization settings' do
    let_it_be(:parent_settings) { { url: 'http://organization.com', password: 'organization' } }
    let_it_be(:parent_integration) do
      # There is no :organization trait. An org-level integration is an :instance row
      # whose organization is not the Default org.
      create(:jira_integration, :instance, organization: project.organization, **parent_settings)
    end

    let(:parent_description) { s_('Integrations|Default settings are inherited from the organization level.') }

    it_behaves_like 'inherited settings'
  end

  context 'with group settings' do
    let_it_be(:group) { create(:group) }
    let_it_be(:project) { create(:project, group: group) }
    let_it_be(:parent_settings) { { url: 'http://group.com', password: 'group' } }
    let_it_be(:parent_integration) { create(:jira_integration, :group, group: group, **parent_settings) }

    let(:parent_description) { s_('Integrations|Default settings are inherited from the group level.') }

    it_behaves_like 'inherited settings'
  end
end
