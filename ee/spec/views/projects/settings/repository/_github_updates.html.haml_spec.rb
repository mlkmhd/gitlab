# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'projects/settings/repository/_github_updates', feature_category: :importers do
  let(:user) { build_stubbed(:user) }
  let(:project) { build_stubbed(:project, import_type: 'github') }
  let(:provider_full_name) { 'octo-org/example' }
  let(:authority_state) { :provider_canonical }
  let(:can_read) { true }
  let(:can_update) { true }
  let(:can_stop) { true }
  let(:import_sync_repository) do
    build_stubbed(
      :import_sync_repository,
      project: project,
      authority_state: authority_state,
      provider_full_name: provider_full_name
    )
  end

  subject(:section) do
    render 'projects/settings/repository/github_updates', project: project
    rendered
  end

  before do
    allow(project).to receive(:import_sync_repository).and_return(import_sync_repository)
    allow(view).to receive(:current_user).and_return(user)
    allow(view).to receive(:can?).with(user, :read_github_update, project).and_return(can_read)
    allow(view).to receive(:can?).with(user, :update_github_update, project).and_return(can_update)
    allow(view).to receive(:can?).with(user, :stop_github_update, project).and_return(can_stop)
    allow(Import::Sync::GithubUpdatesStatusPresenter).to receive(:new) do |repository|
      instance_double(Import::Sync::GithubUpdatesStatusPresenter, to_h: { state: repository.authority_state })
    end
  end

  context 'when the project has an import sync repository' do
    it 'renders its own settings section, which the read-only banner links to', :aggregate_failures do
      expect(section).to have_css('section.settings#github-updates[data-testid="github-updates-settings"]')
      expect(section).to have_css('h2', text: 'GitHub updates')
      expect(section).to have_text(
        'Keep this project updated with changes from GitHub, or stop updates to make changes in GitLab.'
      )
    end

    it 'renders the mount point with the project-scoped endpoints and the exact full path', :aggregate_failures do
      expect(section).to have_css('#github-updates #js-github-updates-settings')
      expect(section).to have_text('Loading GitHub update settings…')
      expect(section).to have_css(
        '#js-github-updates-settings' \
          '[data-status-url$="/-/github_updates/status"]' \
          '[data-update-now-url$="/-/github_updates/update_now"]' \
          '[data-stop-url$="/-/github_updates/stop"]' \
          '[data-repository-name="octo-org/example"]' \
          '[data-repository-url="https://github.com/octo-org/example"]' \
          "[data-initial-status='{\"state\":\"provider_canonical\"}']"
      )
      expect(section).to have_css("#js-github-updates-settings[data-project-full-path=\"#{project.full_path}\"]")
    end
  end

  context 'when the repository name contains URL characters' do
    let(:provider_full_name) { 'octo-org/example?tab=settings' }

    it 'renders the repository name without a link' do
      expect(section).to have_css('#js-github-updates-settings[data-repository-url=""]')
    end
  end

  context 'when the repository name is not an owner and a name' do
    let(:provider_full_name) { 'octo-org' }

    it 'renders the repository name without a link' do
      expect(section).to have_css('#js-github-updates-settings[data-repository-url=""]')
    end
  end

  context 'when GitHub updates have been stopped' do
    let(:authority_state) { :gitlab_canonical }

    it 'passes the status to the frontend' do
      expect(section).to have_css(%q(#js-github-updates-settings[data-initial-status='{"state":"gitlab_canonical"}']))
    end
  end

  context 'when the setup was canceled before syncing started' do
    let(:authority_state) { :bootstrap_canceled }

    it 'does not render the section' do
      expect(section).to be_blank
    end
  end

  context 'when the project has no import sync repository' do
    let(:import_sync_repository) { nil }

    it 'does not render the section' do
      expect(section).to be_blank
    end
  end

  context 'when the project was not imported from GitHub' do
    let(:project) { build_stubbed(:project) }

    it 'does not look up an import sync repository or render the section', :aggregate_failures do
      expect(section).to be_blank
      expect(project).not_to have_received(:import_sync_repository)
    end
  end

  context 'when the user can update GitHub updates but not stop them' do
    let(:can_stop) { false }

    it 'renders the section without the stop URL' do
      expect(section).to have_css(
        '#js-github-updates-settings[data-update-now-url$="/-/github_updates/update_now"][data-stop-url=""]'
      )
    end
  end

  context 'when the user can read GitHub updates but not change them, as on an archived project' do
    let(:can_update) { false }
    let(:can_stop) { false }

    it 'renders the section without the action URLs' do
      expect(section).to have_css('#js-github-updates-settings[data-update-now-url=""][data-stop-url=""]')
    end
  end

  context 'when the user cannot read GitHub updates' do
    let(:can_read) { false }

    it 'does not render the section' do
      expect(section).to be_blank
    end
  end

  # The project stays read-only until it's stopped, so a rollback of the flag must not hide the controls.
  context 'when the github_continuous_import feature flag is disabled' do
    before do
      stub_feature_flags(github_continuous_import: false)
    end

    it 'still renders the section' do
      expect(section).to have_css('#js-github-updates-settings')
    end
  end
end
