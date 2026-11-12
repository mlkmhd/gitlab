# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'Project GitHub updates (JavaScript fixtures)', type: :request, feature_category: :importers do
  include JavaScriptFixturesHelpers

  let_it_be(:project) { create(:project, import_type: 'github') }
  let_it_be(:maintainer) { create(:user, maintainer_of: project) }
  let_it_be(:repository) do
    create(:import_sync_repository, project: project, authority_state: :provider_canonical, application_generation: 2)
  end

  before_all do
    create(:import_sync_repository_state, repository: repository, domain: :inventory, state: :degraded)
    create(
      :import_sync_repository_state,
      repository: repository,
      domain: :source,
      state: :current,
      last_sync_started_at: Time.zone.parse('2026-08-25 15:05:00'),
      last_successful_sync_at: Time.zone.parse('2026-08-25 15:00:00')
    )

    %i[work_items lfs].each do |domain|
      create(:import_sync_repository_state, repository: repository, domain: domain, state: :current)
    end
  end

  before do
    sign_in(maintainer)
  end

  it 'github_updates/status.json' do
    get status_project_github_updates_path(project), as: :json

    expect(response).to have_gitlab_http_status(:ok)
  end

  it 'github_updates/update_now.json' do
    allow(Import::Sync::Repositories::ReconcileWorker).to receive(:perform_async)

    post update_now_project_github_updates_path(project), as: :json

    expect(response).to have_gitlab_http_status(:accepted)
  end
end
