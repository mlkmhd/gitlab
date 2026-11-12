# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Import::Sync::ProjectsHelper, feature_category: :importers do
  using RSpec::Parameterized::TableSyntax

  describe '#github_updates_repository_url' do
    subject(:url) do
      helper.github_updates_repository_url(build_stubbed(:import_sync_repository, provider_full_name: full_name))
    end

    where(:full_name, :expected_url) do
      'octo-org/example'              | 'https://github.com/octo-org/example'
      'octo-org/example?tab=settings' | nil
      'octo-org/..'                   | nil
      'octo-org'                      | nil
      'octo-org/'                     | nil
      '/example'                      | nil
      'octo-org/example/extra'        | nil
      'octo-org//example'             | nil
      ''                              | nil
      nil                             | nil
    end

    with_them do
      it { is_expected.to eq(expected_url) }
    end

    context 'when the project was imported from another GitHub host' do
      subject(:url) do
        helper.github_updates_repository_url(
          build_stubbed(:import_sync_repository, project: project, provider_full_name: 'octo-org/example')
        )
      end

      let(:project) { build_stubbed(:project, import_url: import_url) }

      context 'with a GitHub Enterprise Server URL' do
        let(:import_url) { 'https://user:secret@ghe.example.com:8443/octo-org/example.git' }

        it 'links to that host without the credentials' do
          expect(url).to eq('https://ghe.example.com:8443/octo-org/example')
        end
      end

      context 'with an import URL that cannot be parsed' do
        let(:import_url) { 'https://ghe example.com/octo-org/example.git' }

        it { is_expected.to be_nil }
      end
    end
  end

  describe '#github_updates_settings_data' do
    subject(:data) { helper.github_updates_settings_data(project, repository) }

    let(:project) { build_stubbed(:project) }
    let(:repository) { build_stubbed(:import_sync_repository, project: project, provider_full_name: full_name) }
    let(:full_name) { 'octo-org/example' }
    let(:status) { { state: 'provider_canonical', read_only: true, final_pass_incomplete: false, data: {} } }

    let(:user) { build_stubbed(:user) }
    let(:can_update) { true }
    let(:can_stop) { true }

    before do
      allow(Import::Sync::GithubUpdatesStatusPresenter).to receive(:new).with(repository)
        .and_return(instance_double(Import::Sync::GithubUpdatesStatusPresenter, to_h: status))
      allow(helper).to receive(:current_user).and_return(user)
      allow(helper).to receive(:can?).with(user, :update_github_update, project).and_return(can_update)
      allow(helper).to receive(:can?).with(user, :stop_github_update, project).and_return(can_stop)
    end

    it 'returns the settings app data' do
      expect(data).to eq(
        status_url: "/#{project.full_path}/-/github_updates/status",
        update_now_url: "/#{project.full_path}/-/github_updates/update_now",
        stop_url: "/#{project.full_path}/-/github_updates/stop",
        project_full_path: project.full_path,
        repository_name: 'octo-org/example',
        repository_url: 'https://github.com/octo-org/example',
        initial_status: status.to_json
      )
    end

    context 'when the user cannot stop GitHub updates' do
      let(:can_stop) { false }

      it 'leaves out the stop URL' do
        expect(data[:stop_url]).to eq('')
      end
    end

    context 'when the user cannot update GitHub updates' do
      let(:can_update) { false }

      it 'leaves out the update now URL' do
        expect(data[:update_now_url]).to eq('')
      end
    end
  end

  describe '#github_updates_read_only_notice_body' do
    subject(:body) { helper.github_updates_read_only_notice_body(project) }

    let(:project) { build_stubbed(:project) }
    let(:user) { build_stubbed(:user) }
    let(:can_read) { true }
    let(:import_sync_repository) { build_stubbed(:import_sync_repository, project: project, authority_state: state) }
    let(:updates_on) do
      s_('GithubUpdatesReadOnly|Updates from GitHub are on for this project. Make changes in GitHub.')
    end

    let(:connection_lost) do
      s_('GithubUpdatesReadOnly|GitLab lost its connection to GitHub. This project stays read-only until GitLab ' \
        'can check GitHub for the latest changes.')
    end

    let(:setting_up) do
      s_('GithubUpdatesReadOnly|GitLab is setting up updates from GitHub. This project stays read-only until the ' \
        'setup finishes.')
    end

    let(:stop_failed) do
      s_("GithubUpdatesReadOnly|GitLab couldn't stop GitHub updates. This project stays read-only until updates stop.")
    end

    let(:stopping) do
      s_('GithubUpdatesReadOnly|GitHub updates are stopping. This project stays read-only until GitLab finishes a ' \
        'final check of GitHub.')
    end

    before do
      allow(project).to receive(:import_sync_repository).and_return(import_sync_repository)
      allow(helper).to receive(:current_user).and_return(user)
      allow(helper).to receive(:can?).with(user, :read_github_update, project).and_return(can_read)
    end

    where(:state, :expected_body) do
      'provisioning'       | ref(:setting_up)
      'provider_canonical' | ref(:updates_on)
      'disconnected'       | ref(:connection_lost)
      'cutting_over'       | ref(:stopping)
      'cutover_failed'     | ref(:stop_failed)
    end

    with_them do
      it { is_expected.to eq(expected_body) }
    end

    context 'when the project has no import sync repository' do
      let(:import_sync_repository) { nil }

      it { is_expected.to be_nil }
    end

    context 'when the user cannot read GitHub updates' do
      let(:can_read) { false }
      let(:state) { 'disconnected' }

      it { is_expected.to eq(updates_on) }
    end
  end

  describe '#show_github_updates_settings?' do
    subject(:show_settings) { helper.show_github_updates_settings?(repository) }

    context 'without an import sync repository' do
      let(:repository) { nil }

      it { is_expected.to be(false) }
    end

    context 'when the setup was canceled before syncing started' do
      let(:repository) { build_stubbed(:import_sync_repository, authority_state: :bootstrap_canceled) }

      it { is_expected.to be(false) }
    end

    (Import::Sync::Repository.authority_states.keys - ['bootstrap_canceled']).each do |authority_state|
      context "when the authority state is #{authority_state}" do
        let(:repository) { build_stubbed(:import_sync_repository, authority_state: authority_state) }

        it { is_expected.to be(true) }
      end
    end
  end

  describe '#show_github_updates_notice?' do
    subject(:show_notice) { helper.show_github_updates_notice?(project) }

    let(:project) { build_stubbed(:project) }

    [true, false].each do |read_only|
      context "when the project read-only state is #{read_only}" do
        before do
          allow(Import::Sync::Projects::WritePolicy).to receive(:read_only?).with(project).and_return(read_only)
        end

        it { is_expected.to be(read_only) }
      end
    end
  end
end
