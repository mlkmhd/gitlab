# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'projects/_github_updates_notice', feature_category: :importers do
  subject(:page_level_alert) { view.content_for(:page_level_alert) }

  let(:user) { build_stubbed(:user) }
  let(:project) { build_stubbed(:project, import_type: 'github') }
  let(:import_sync_repository) do
    build_stubbed(
      :import_sync_repository,
      project: project,
      authority_state: authority_state,
      provider_full_name: provider_full_name
    )
  end

  let(:provider_full_name) { 'octo-org/example' }
  let(:authority_state) { :provider_canonical }
  let(:can_read) { true }
  let(:can_update) { true }
  let(:can_read_code) { true }
  let(:read_only_title) { s_('GithubUpdatesReadOnly|This project is read-only') }
  let(:view_on_github) { s_('GithubUpdatesReadOnly|View on GitHub') }
  let(:manage_github_updates) { s_('GithubUpdatesReadOnly|Manage GitHub updates') }
  let(:updates_on) { s_('GithubUpdatesReadOnly|Updates from GitHub are on for this project. Make changes in GitHub.') }
  let(:notice_bodies) do
    {
      'provisioning' => s_('GithubUpdatesReadOnly|GitLab is setting up updates from GitHub. This project stays ' \
        'read-only until the setup finishes.'),
      'provider_canonical' => updates_on,
      'disconnected' => s_('GithubUpdatesReadOnly|GitLab lost its connection to GitHub. This project stays ' \
        'read-only until GitLab can check GitHub for the latest changes.'),
      'cutting_over' => s_('GithubUpdatesReadOnly|GitHub updates are stopping. This project stays read-only until ' \
        'GitLab finishes a final check of GitHub.'),
      'cutover_failed' => s_("GithubUpdatesReadOnly|GitLab couldn't stop GitHub updates. This project stays " \
        'read-only until updates stop.')
    }
  end

  before do
    allow(project).to receive(:import_sync_repository).and_return(import_sync_repository)
    allow(view).to receive_messages(current_user: user)
    allow(view).to receive(:can?).with(user, :read_github_update, project).and_return(can_read)
    allow(view).to receive(:can?).with(user, :update_github_update, project).and_return(can_update)
    allow(view).to receive(:can?).with(user, :read_code, project).and_return(can_read_code)

    render 'projects/github_updates_notice', project: project
  end

  Import::Sync::Repository::READ_ONLY_AUTHORITY_STATES.each do |read_only_state|
    context "when the authority state is #{read_only_state}" do
      let(:authority_state) { read_only_state }
      let(:body) { notice_bodies.fetch(read_only_state) }

      it 'renders one alert that explains the state', :aggregate_failures do
        expect(page_level_alert).to have_css('.gl-alert-info', count: 1)
        expect(page_level_alert).to have_text(read_only_title)
        expect(page_level_alert).to have_text(body)
        expect(page_level_alert).to have_link(view_on_github, href: 'https://github.com/octo-org/example')
      end
    end
  end

  context 'when the user can update GitHub updates' do
    it 'links to the GitHub updates section of the repository settings' do
      expect(page_level_alert).to have_link(manage_github_updates, href: %r{/settings/repository#github-updates\z})
    end
  end

  context 'when the user can only read GitHub updates' do
    let(:can_update) { false }

    it 'only links to the repository on GitHub', :aggregate_failures do
      expect(page_level_alert).to have_link(view_on_github)
      expect(page_level_alert).not_to have_link(manage_github_updates)
    end
  end

  context 'when the user can read the code but not GitHub updates' do
    let(:can_read) { false }
    let(:can_update) { false }
    let(:authority_state) { :disconnected }

    it 'links to the repository on GitHub without its connection state', :aggregate_failures do
      expect(page_level_alert).to have_text(read_only_title)
      expect(page_level_alert).to have_text(updates_on)
      expect(page_level_alert).not_to have_text(notice_bodies.fetch('disconnected'))
      expect(page_level_alert).to have_link(view_on_github, href: 'https://github.com/octo-org/example')
      expect(page_level_alert).not_to have_link(manage_github_updates)
    end
  end

  context 'when the user cannot read the code' do
    let(:can_read) { false }
    let(:can_update) { false }
    let(:can_read_code) { false }

    it 'does not link to the repository on GitHub' do
      expect(page_level_alert).not_to have_link(view_on_github)
    end
  end

  context 'when no user is signed in to a public project' do
    let(:user) { nil }
    let(:can_read) { false }
    let(:can_update) { false }

    it 'explains that the project is read-only without links', :aggregate_failures do
      expect(page_level_alert).to have_text(updates_on)
      expect(page_level_alert).not_to have_link(view_on_github)
      expect(page_level_alert).not_to have_link(manage_github_updates)
    end
  end

  context 'when the repository name is not an owner and a name' do
    let(:provider_full_name) { 'octo-org' }

    it 'keeps the settings link without a link to GitHub', :aggregate_failures do
      expect(page_level_alert).not_to have_link(view_on_github)
      expect(page_level_alert).to have_link(manage_github_updates)
    end
  end

  context 'when GitHub updates have been stopped' do
    let(:authority_state) { :gitlab_canonical }

    it 'does not render the alert' do
      expect(page_level_alert).to be_blank
    end
  end

  context 'when the project has no import sync repository' do
    let(:import_sync_repository) { nil }

    it 'does not render the alert' do
      expect(page_level_alert).to be_blank
    end
  end
end
