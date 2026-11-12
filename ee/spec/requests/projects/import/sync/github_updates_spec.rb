# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'Project GitHub updates', :aggregate_failures, feature_category: :importers do
  let_it_be(:project) { create(:project, import_type: 'github') }
  let_it_be_with_reload(:repository) do
    create(:import_sync_repository, project: project, authority_state: :provider_canonical, application_generation: 2)
  end

  let_it_be(:maintainer) { create(:user, maintainer_of: project) }
  let_it_be(:developer) { create(:user, developer_of: project) }
  let_it_be(:auditor) { create(:auditor) }

  let(:user) { maintainer }
  let(:requested_project) { project }
  let(:status_path) { status_project_github_updates_path(requested_project) }
  let(:update_now_path) { update_now_project_github_updates_path(requested_project) }
  let(:stop_path) { stop_project_github_updates_path(requested_project) }

  before_all do
    %i[inventory source work_items].each do |domain|
      create(
        :import_sync_repository_state,
        repository: repository,
        domain: domain,
        state: :current,
        last_sync_started_at: Time.zone.parse('2026-08-25 15:05:00'),
        last_successful_sync_at: Time.zone.parse('2026-08-25 15:00:00')
      )
    end
  end

  before do
    sign_in(user) if user
  end

  shared_examples 'an action on a project with GitHub updates' do
    context 'when the user is not a member of the project' do
      let(:user) { create(:user) }

      it 'does not find the page' do
        request

        expect(response).to have_gitlab_http_status(:not_found)
      end
    end

    context 'when the user is not signed in' do
      let(:user) { nil }

      it 'redirects to sign in' do
        request

        expect(response).to redirect_to(new_user_session_path)
      end
    end

    context 'when the project has no import sync repository' do
      let_it_be(:requested_project) { create(:project, import_type: 'github', maintainers: maintainer) }

      it 'does not find the page' do
        request

        expect(response).to have_gitlab_http_status(:not_found)
      end
    end

    # The project stays read-only until it's stopped, so a rollback of the flag must not strand it.
    context 'when the github_continuous_import feature flag is disabled' do
      before do
        stub_feature_flags(github_continuous_import: false)
      end

      it 'still serves the action' do
        request

        expect(response).to have_gitlab_http_status(:success)
      end
    end
  end

  shared_examples 'an action that updates GitHub updates' do
    it_behaves_like 'an action on a project with GitHub updates'

    [:developer, :auditor].each do |role|
      context "when the user is a #{role}" do
        let(:user) { public_send(role) }

        it 'does not find the page' do
          request

          expect(response).to have_gitlab_http_status(:not_found)
        end
      end
    end

    %i[archived aimed_for_deletion].each do |trait|
      context "when the project is #{trait.to_s.humanize(capitalize: false)}" do
        let_it_be(:requested_project) { create(:project, trait, import_type: 'github', maintainers: maintainer) }

        before_all do
          create(:import_sync_repository, project: requested_project, authority_state: :provider_canonical)
        end

        it 'does not find the page' do
          request

          expect(response).to have_gitlab_http_status(:not_found)
        end
      end
    end
  end

  describe 'the status in the repository settings' do
    let(:request) { get project_settings_repository_path(project) }

    def initial_status
      Gitlab::Json::SafeParser.parse(Nokogiri::HTML(response.body).at_css('#js-github-updates-settings')['data-initial-status'])
    end

    it 'renders the authority state, the read-only flag and the state of every data domain' do
      request

      expect(response).to have_gitlab_http_status(:ok)
      expect(initial_status).to match(
        'state' => 'provider_canonical',
        'read_only' => true,
        'final_pass_incomplete' => false,
        'data' => {
          'inventory' => an_instance_of(Hash),
          'source' => {
            'state' => 'current',
            'last_updated_at' => '2026-08-25T15:00:00.000Z',
            'last_checked_at' => '2026-08-25T15:05:00.000Z'
          },
          'work_items' => an_instance_of(Hash)
        }
      )
    end

    context 'when GitHub updates have been stopped' do
      before do
        repository.update!(authority_state: :gitlab_canonical)
      end

      it 'reports the project as writable' do
        request

        expect(initial_status).to include(
          'state' => 'gitlab_canonical',
          'read_only' => false,
          'final_pass_incomplete' => false
        )
      end

      %i[current pending degraded].each do |stored_state|
        context "when a data type has requested work that was never applied and is stored as #{stored_state}" do
          before do
            repository.sync_states.find_by!(domain: :work_items)
              .update!(desired_generation: 2, synced_generation: 1, state: stored_state)
          end

          it 'reports that the final pass is incomplete' do
            request

            expect(initial_status).to include('state' => 'gitlab_canonical', 'final_pass_incomplete' => true)
          end
        end
      end
    end

    # A canceled setup shows no settings section.
    (Import::Sync::Repository.authority_states.keys - %w[gitlab_canonical bootstrap_canceled]).each do |authority_state|
      context "when the project is #{authority_state} and a data type has requested work" do
        before do
          repository.update_column(:authority_state, authority_state)
          repository.sync_states.find_by!(domain: :source).update!(desired_generation: 2, synced_generation: 1)
        end

        it 'does not report an incomplete final pass' do
          request

          expect(initial_status).to include('state' => authority_state, 'final_pass_incomplete' => false)
        end
      end
    end

    # Drives the real stop services, to check that a lagging data type really identifies a stop that skipped
    # the final pass.
    context 'when the project is stopped by the real stop services', :clean_gitlab_redis_shared_state do
      let(:import_status) { :finished }

      def apply_final_pass
        repository.sync_states.each do |state|
          state.update!(synced_generation: state.desired_generation, state: :current)
        end

        { applied_domains: [], follow_up: false }
      end

      def stop_and_finish
        post stop_path, as: :json
        expect(response).to have_gitlab_http_status(:accepted)

        Import::Sync::Repositories::FinishStopService
          .new(repository.reload, application_generation: repository.application_generation)
          .execute
      end

      before do
        allow(Import::Sync::Repositories::FinishStopWorker).to receive(:perform_async)
        ProjectImportState.create!(project_id: project.id, status: import_status)
      end

      context 'when the final pass ran' do
        before do
          allow_next_instance_of(Import::Sync::Repositories::ReconcileSourceService) do |service|
            allow(service).to receive(:execute) { apply_final_pass }
          end

          allow_next_instance_of(Import::Sync::Repositories::ReconcileWorkItemsService) do |service|
            allow(service).to receive(:execute) { apply_final_pass }
          end
        end

        it 'does not report an incomplete final pass' do
          expect(stop_and_finish).to be(true)

          request

          expect(initial_status).to include('state' => 'gitlab_canonical', 'final_pass_incomplete' => false)
        end
      end

      context 'when the GitHub repository is gone' do
        before do
          allow_next_instance_of(Import::Sync::Repositories::ReconcileSourceService) do |service|
            allow(service).to receive(:execute).and_raise(Octokit::NotFound)
          end
        end

        it 'reports an incomplete final pass' do
          expect(stop_and_finish).to be(true)

          request

          expect(initial_status).to include('state' => 'gitlab_canonical', 'final_pass_incomplete' => true)
        end
      end

      context 'when the import did not finish' do
        let(:import_status) { :failed }

        it 'reports an incomplete final pass' do
          expect(stop_and_finish).to be(true)

          request

          expect(initial_status).to include('state' => 'gitlab_canonical', 'final_pass_incomplete' => true)
        end
      end
    end
  end

  describe 'GET status' do
    let(:request) { get status_path, as: :json }

    it_behaves_like 'an action on a project with GitHub updates'

    context 'when the user is a developer' do
      let(:user) { developer }

      it 'does not find the page' do
        request

        expect(response).to have_gitlab_http_status(:not_found)
      end
    end

    context 'when the user is an auditor' do
      let(:user) { auditor }

      it 'returns the status' do
        request

        expect(response).to have_gitlab_http_status(:ok)
        expect(json_response).to include('state' => 'provider_canonical')
      end
    end

    it 'returns the same status as the repository settings and asks the client to poll again in five seconds' do
      request

      expect(response).to have_gitlab_http_status(:ok)
      expect(json_response).to include('state' => 'provider_canonical', 'read_only' => true)
      expect(json_response.dig('data', 'source')).to eq(
        'state' => 'current',
        'last_updated_at' => '2026-08-25T15:00:00.000Z',
        'last_checked_at' => '2026-08-25T15:05:00.000Z'
      )
      expect(response.headers['Poll-Interval']).to eq('5000')
    end

    context 'when GitHub updates have been stopped' do
      before do
        repository.update!(authority_state: :gitlab_canonical)
      end

      it 'tells the client to stop polling' do
        request

        expect(json_response).to include('state' => 'gitlab_canonical', 'read_only' => false)
        expect(response.headers['Poll-Interval']).to eq('-1')
      end
    end
  end

  describe 'POST update_now' do
    let(:request) { post update_now_path, as: :json }

    before do
      allow(Import::Sync::Repositories::ReconcileWorker).to receive(:perform_async)
    end

    it_behaves_like 'an action that updates GitHub updates'

    it 'schedules every data domain and enqueues a reconcile at the current application generation' do
      request

      expect(Import::Sync::Repositories::ReconcileWorker).to have_received(:perform_async).with(repository.id, 2)
      expect(response).to have_gitlab_http_status(:accepted)
      expect(json_response).to include(
        'message' => 'Update scheduled.',
        'state' => 'provider_canonical'
      )
      expect(json_response.dig('data', 'source', 'state')).to eq('pending')
    end

    (Import::Sync::Repository.authority_states.keys - %w[provisioning provider_canonical]).each do |authority_state|
      context "when the authority state is #{authority_state}" do
        before do
          repository.update_column(:authority_state, authority_state)
        end

        it 'returns an error and enqueues nothing' do
          request

          expect(Import::Sync::Repositories::ReconcileWorker).not_to have_received(:perform_async)
          expect(response).to have_gitlab_http_status(:unprocessable_entity)
          expect(json_response).to eq(
            'error' => 'github_updates_not_updatable',
            'message' => 'An update can only be requested while GitHub updates are on and not being stopped. ' \
              'Refresh the page to see the current status.'
          )
        end
      end
    end
  end

  describe 'POST stop', :clean_gitlab_redis_shared_state do
    let(:request) { post stop_path, as: :json }
    let(:not_stoppable_response) do
      {
        'error' => 'github_updates_not_stoppable',
        'message' => 'GitHub updates cannot be stopped right now. Refresh the page and try again.'
      }
    end

    let(:busy_response) do
      {
        'error' => 'github_updates_busy',
        'message' => 'GitHub updates are still finishing. Try stopping updates again.'
      }
    end

    before do
      allow(Import::Sync::Repositories::FinishStopWorker).to receive(:perform_async)
    end

    it_behaves_like 'an action that updates GitHub updates'

    context 'when the user can update GitHub updates but not stop them' do
      before do
        allow(Ability).to receive(:allowed?).and_call_original
        allow(Ability).to receive(:allowed?).with(maintainer, :stop_github_update, project).and_return(false)
      end

      it 'does not find the page and keeps GitHub updates on' do
        expect(Ability.allowed?(maintainer, :update_github_update, project)).to be(true)

        request

        expect(response).to have_gitlab_http_status(:not_found)
        expect(repository.reload).to be_provider_canonical
        expect(Import::Sync::Repositories::FinishStopWorker).not_to have_received(:perform_async)
      end
    end

    context 'when GitHub updates are on' do
      it 'starts the stop, audits it and returns the status with the new generation' do
        expect(::Gitlab::Audit::Auditor).to receive(:audit)
          .with(hash_including(name: 'github_updates_stop_requested', author: maintainer, scope: project))

        request

        expect(response).to have_gitlab_http_status(:accepted)
        expect(json_response).to include('state' => 'cutting_over', 'read_only' => true)
        expect(json_response).not_to have_key('application_generation')
        expect(json_response.fetch('data').keys).to contain_exactly('inventory', 'source', 'work_items', 'lfs')
        expect(json_response.dig('data', 'source', 'state')).to eq('pending')
        expect(repository.reload).to be_cutting_over
        expect(Import::Sync::Repositories::FinishStopWorker).to have_received(:perform_async).with(repository.id, 3)
      end
    end

    context 'when a previous stop failed' do
      before do
        repository.update!(authority_state: :cutover_failed)
      end

      it 'starts the stop again' do
        request

        expect(response).to have_gitlab_http_status(:accepted)
        expect(json_response).to include('state' => 'cutting_over')
        expect(Import::Sync::Repositories::FinishStopWorker).to have_received(:perform_async).with(repository.id, 3)
      end
    end

    context 'when GitHub updates were already stopped' do
      before do
        repository.update!(authority_state: :gitlab_canonical)
      end

      it 'returns a not stoppable error' do
        request

        expect(response).to have_gitlab_http_status(:unprocessable_entity)
        expect(json_response).to eq(not_stoppable_response)
      end
    end

    context 'when a stop was already requested' do
      before do
        repository.update!(authority_state: :cutting_over, application_generation: 3)
      end

      it 'returns the status of the running stop' do
        request

        expect(response).to have_gitlab_http_status(:accepted)
        expect(json_response).to include('state' => 'cutting_over')
      end
    end

    context 'when the connection to GitHub was lost' do
      before do
        repository.disconnect!(:token_revoked)
      end

      it 'returns a connection lost error without the exception message' do
        request

        expect(response).to have_gitlab_http_status(:unprocessable_entity)
        expect(json_response).to eq(
          'error' => 'github_connection_lost',
          'message' => 'GitLab must check GitHub for the latest changes before this project can be made editable.'
        )
      end
    end

    context 'when GitHub updates cannot be stopped from their current state' do
      before do
        repository.update!(authority_state: :provisioning)
      end

      it 'returns a not stoppable error without the exception message' do
        request

        expect(response).to have_gitlab_http_status(:unprocessable_entity)
        expect(json_response).to eq(not_stoppable_response)
        expect(repository.reload).to be_provisioning
      end
    end

    context 'when the import is still running' do
      before do
        Project.where(id: project.id).update_all(import_url: 'https://github.com/octo-org/example.git')
        ProjectImportState.create!(project_id: project.id, status: :started)
      end

      it 'tells the user to wait for the import and leaves the project as it was' do
        request

        expect(response).to have_gitlab_http_status(:unprocessable_entity)
        expect(json_response).to eq(
          'error' => 'github_updates_not_stoppable',
          'message' => 'Wait for the import to finish, then stop GitHub updates.'
        )
        expect(repository.reload).to be_provider_canonical
        expect(Import::Sync::Repositories::FinishStopWorker).not_to have_received(:perform_async)
      end
    end

    context 'when another operation holds the repository lease' do
      before do
        lease_key = Import::Sync::Repositories::ApplicationLease.key(repository.id)
        Gitlab::ExclusiveLease.new(lease_key, timeout: 1.minute).try_obtain
      end

      it 'returns a busy error' do
        request

        expect(response).to have_gitlab_http_status(:conflict)
        expect(json_response).to eq(busy_response)
        expect(repository.reload).to be_provider_canonical
      end
    end

    context 'when the repository lease is lost during the stop' do
      before do
        allow_next_instance_of(Import::Sync::Repositories::RequestStopService) do |service|
          allow(service).to receive(:execute)
            .and_raise(Import::Sync::Repositories::ApplicationLease::LostLeaseError)
        end
      end

      it 'returns the same busy error instead of failing' do
        request

        expect(response).to have_gitlab_http_status(:conflict)
        expect(json_response).to eq(busy_response)
      end
    end
  end

  describe 'pages that show GitHub updates' do
    using RSpec::Parameterized::TableSyntax

    let(:notice) { Nokogiri::HTML(response.body).at_css('[data-testid="github-updates-notice"]') }
    let(:links) { notice.css('a').map(&:text).map(&:strip) }
    let(:view_on_github) { s_('GithubUpdatesReadOnly|View on GitHub') }

    where(:role, :full_details, :can_manage) do
      :maintainer | true  | true
      :auditor    | true  | false
      :developer  | false | false
    end

    with_them do
      let(:user) { public_send(role) }
      let(:connection_lost) do
        s_('GithubUpdatesReadOnly|GitLab lost its connection to GitHub. This project stays read-only until GitLab ' \
          'can check GitHub for the latest changes.')
      end

      before do
        repository.disconnect!(:token_revoked)
      end

      it 'renders the read-only banner with what the user can see' do
        get project_path(project)

        expect(response).to have_gitlab_http_status(:ok)
        expect(notice.text.include?(connection_lost)).to be(full_details)
        expect(links).to include(view_on_github)
        expect(links.include?(s_('GithubUpdatesReadOnly|Manage GitHub updates'))).to be(can_manage)
      end
    end

    context 'when no user is signed in to a public project' do
      let_it_be(:public_project) { create(:project, :public, import_type: 'github') }
      let(:user) { nil }

      before_all do
        create(:import_sync_repository, project: public_project, authority_state: :provider_canonical)
      end

      it 'renders the read-only banner without links' do
        get project_path(public_project)

        expect(response).to have_gitlab_http_status(:ok)
        expect(notice.text).to include(
          s_('GithubUpdatesReadOnly|Updates from GitHub are on for this project. Make changes in GitHub.')
        )
        expect(links).to be_empty
      end
    end

    it 'renders the GitHub updates section in the repository settings' do
      get project_settings_repository_path(project)

      expect(response).to have_gitlab_http_status(:ok)
      expect(response.body).to include('id="js-github-updates-settings"')
    end

    it 'does not render the read-only banner in the repository settings, which show the status instead' do
      get project_settings_repository_path(project)

      expect(response).to have_gitlab_http_status(:ok)
      expect(response.body).to include('id="js-github-updates-settings"')
      expect(notice).to be_nil
    end
  end
end
