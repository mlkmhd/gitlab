# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'Organization Artifact Registry repository access', :js, :with_current_organization,
  feature_category: :artifact_registry do
  include_context 'with a signed-in organization member and an active Artifact Registry'
  include_context 'with a repository the Artifact Registry client returns'

  let(:name) { 'maven-releases' }
  let(:format) { 'maven' }
  let(:repository_path) { "#{repositories_base_path}/#{name}" }

  let(:repository_attributes) do
    default_repository_attributes.merge('artifacts_count' => 0, 'downloads_count' => 0, 'size_bytes' => 0)
  end

  before do
    stub_feature_flags(artifact_registry_repository_role_management_ui: current_organization)

    allow(::ArtifactRegistry::Client).to receive(:new).with(current_user: user).and_return(client)
    allow(client).to receive_messages(verify_repositories: [], packages: ::ArtifactRegistry::Page.new(nodes: []))
    allow(client).to receive(:repository_statistics)
      .with(slug: slug, repository_name: name, format: 'maven')
      .and_return(::ArtifactRegistry::RepositoryStatistics.new('packages_count' => 0))
    allow_next_instance_of(::ArtifactRegistry::LookupRoleAssignmentsService) do |service|
      allow(service).to receive(:execute)
        .and_return(ServiceResponse.success(payload: { role_assignments: [], next_page_token: '' }))
    end

    visit repository_path
  end

  def open_access_panel
    within_testid('repositories-shell') do
      click_button("More actions for #{name}")

      within_testid('disclosure-content') do
        click_button('Manage access')
      end
    end
  end

  it 'opens a region named by its title that holds the Organization access note', :aggregate_failures do
    open_access_panel

    panel = find('[role="region"][data-testid="access-side-panel"]')
    heading = find_by_testid('access-heading')

    expect(heading).to have_text("Access for #{name}")
    expect(heading['id']).to be_present
    expect(panel['aria-labelledby']).to eq(heading['id'])

    within(panel) do
      expect(page).to have_text('Members with a role in Organization access also have access to this repository.')
    end
  end

  it 'passes axe automated accessibility testing' do
    open_access_panel

    expect(page).to have_testid('access-side-panel')
    expect(page).to be_axe_clean.within_testid('access-side-panel')
  end

  it 'opens the Add members modal that passes axe automated accessibility testing' do
    open_access_panel

    within_testid('access-side-panel') do
      click_button('Add members')
    end

    expect(page).to have_css('[role="dialog"] h2', text: 'Add members')
    expect(page).to have_text("You're adding members to the #{name} repository.")
    expect(page).to be_axe_clean.within('[role="dialog"]')
  end

  it 'takes focus, closes on Escape, and gives focus back to the actions toggle' do
    open_access_panel

    expect(page).to have_css('[data-testid="access-side-panel"]:focus')

    send_keys :escape

    expect(page).to have_no_testid('access-side-panel')
    expect(page).to have_button("More actions for #{name}", focused: true)
  end
end
