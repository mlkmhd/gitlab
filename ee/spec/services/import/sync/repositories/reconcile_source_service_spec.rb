# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Import::Sync::Repositories::ReconcileSourceService, feature_category: :importers do
  let(:sync_repository) do
    create(:import_sync_repository, :oauth, authority_state: :provider_canonical, provider_repository_xid: 123)
  end

  let(:inventory_state) { create(:import_sync_repository_state, repository: sync_repository, domain: :inventory) }
  let(:source_state) { create(:import_sync_repository_state, repository: sync_repository, domain: :source) }
  let(:project) { sync_repository.project }
  let(:application_generation) { sync_repository.application_generation }
  let(:git_repository) { instance_double(Repository) }
  let(:raw_repository) { instance_double(Gitlab::Git::Repository, root_ref: 'master') }
  let(:authentication) do
    instance_double(
      Import::Sync::Repositories::Authentication,
      repository_url: 'https://github.com/example/renamed.git',
      http_authorization_header: 'Basic redacted',
      resolved_address: ''
    )
  end

  let(:provider_repository) do
    {
      id: 123,
      node_id: sync_repository.provider_repository_node_id,
      full_name: 'example/renamed',
      default_branch: 'main'
    }
  end

  let(:client) { instance_double(Gitlab::GithubImport::Client, repository: provider_repository) }
  let(:lease) { instance_double(Import::Sync::Repositories::ApplicationLease) }
  let(:lease_context) do
    instance_double(
      Import::Sync::Repositories::ApplicationLease::Context,
      verify!: true,
      verify_repository!: true,
      renew!: true
    )
  end

  let(:lfs_state) do
    create(:import_sync_repository_state, repository: sync_repository, domain: :lfs, state: :current)
  end

  let(:fetch_result) { Gitaly::FetchRemoteResponse.new(repo_changed: true) }
  let(:current_time) { Time.zone.parse('2026-08-25 13:00:00') }

  subject(:service) do
    described_class.new(
      sync_repository,
      application_generation: application_generation,
      now: -> { current_time }
    )
  end

  before do
    [inventory_state, source_state].each { |state| state.update!(desired_generation: 2, synced_generation: 1) }
    allow(Import::Sync::Repositories::ApplicationLease).to receive(:new).and_return(lease)
    allow(lease).to receive(:execute).and_yield(lease_context)
    allow(project).to receive_messages(repository: git_repository, default_branch: 'main')
    allow(project).to receive(:touch)
    allow(git_repository).to receive_messages(fetch_as_mirror: fetch_result, raw_repository: raw_repository)
    allow(git_repository).to receive(:change_head)
    allow(git_repository).to receive(:log_geo_updated_event)
    allow(git_repository).to receive(:expire_all_method_caches)
    allow(raw_repository).to receive(:list_refs).and_return([])
    allow(authentication).to receive(:client).with(parallel: true).and_return(client)
    allow(Import::Sync::Repositories::Authentication).to receive(:for)
      .with(sync_repository)
      .and_return(authentication)
    allow(Import::Sync::Repositories::ReconcileLfsObjectsService).to receive(:new)
  end

  it 'updates stable metadata and fetches only provider-owned heads and tags' do
    expect(Git::BranchPushService).not_to receive(:new)
    expect(ProjectCacheWorker).to receive(:perform_async).with(project.id, [], %w[repository_size commit_count])

    result = service.execute

    expect(client).to have_received(:repository).with(123)
    expect(git_repository).to have_received(:fetch_as_mirror).with(
      'https://github.com/example/renamed.git',
      refmap: described_class::PROVIDER_REFMAP,
      forced: true,
      no_tags: true,
      prune: true,
      http_authorization_header: 'Basic redacted',
      resolved_address: ''
    )
    expect(git_repository).to have_received(:change_head).with('main')
    expect(Import::Sync::Repositories::ReconcileLfsObjectsService).not_to have_received(:new)
    expect(project).to have_received(:touch).with(:last_repository_updated_at)
    expect(sync_repository.reload.provider_full_name).to eq('example/renamed')
    expect(result).to eq(
      applied_domains: %w[inventory source],
      follow_up: false,
      lfs_revisions: { generation: 2, revisions: [] }
    )
    expect(inventory_state.reload).to have_attributes(
      synced_generation: 2,
      state: 'current',
      last_successful_sync_at: current_time
    )
    expect(source_state.reload).to have_attributes(
      synced_generation: 2,
      state: 'current',
      last_successful_sync_at: current_time
    )
  end

  it 'uses the lease context of the caller instead of taking a new lease' do
    described_class.new(sync_repository, application_generation: application_generation, now: -> { current_time })
      .execute(lease_context: lease_context)

    expect(lease_context).to have_received(:verify_repository!).with(sync_repository.id)
    expect(Import::Sync::Repositories::ApplicationLease).not_to have_received(:new)
  end

  it 'renews the lease and re-checks the fence after the fetch returns, before HEAD moves' do
    calls = []
    allow(client).to receive(:repository) do
      calls << :provider_repository
      provider_repository
    end
    allow(lease_context).to receive(:renew!) { calls << :renew }
    allow(lease_context).to receive(:verify!) { calls << :verify }
    allow(git_repository).to receive(:fetch_as_mirror) do
      calls << :fetch_as_mirror
      fetch_result
    end
    allow(git_repository).to receive(:change_head) { calls << :change_head }
    allow(git_repository).to receive(:expire_all_method_caches) { calls << :expire_caches }
    allow(project).to receive(:touch) { calls << :touch }

    service.execute

    expect(calls).to eq(%i[
      provider_repository renew verify
      verify fetch_as_mirror expire_caches renew verify change_head
      touch verify
    ])
  end

  it 'creates the LFS row and asks for an LFS pass when the repository has no LFS row yet' do
    service.execute

    expect(sync_repository.sync_states.find_by!(domain: :lfs)).to have_attributes(desired_generation: 2)
  end

  context 'when the fetch changes refs' do
    before do
      lfs_state
    end

    it 'asks for an LFS pass without waiting for it' do
      expect(service.execute).to eq(
        applied_domains: %w[inventory source],
        follow_up: false,
        lfs_revisions: { generation: 1, revisions: [] }
      )

      expect(lfs_state.reload).to have_attributes(desired_generation: 1, synced_generation: 0, state: 'pending')
    end

    it 'hands the LFS pass the revisions the fetch changed, with the generation it asked for' do
      allow(raw_repository).to receive(:list_refs).with(described_class::LFS_REF_PREFIXES).and_return(
        [ref('refs/heads/main', 'a1'), ref('refs/heads/moved', 'b1'), ref('refs/heads/deleted', 'c1')],
        [ref('refs/heads/main', 'a1'), ref('refs/heads/moved', 'b2'), ref('refs/tags/v1', 'd1')]
      )

      expect(service.execute[:lfs_revisions]).to eq(generation: 1, revisions: %w[b1..b2 a1..d1])
    end

    it 'skips a new ref that points at the default branch tip from before the fetch' do
      allow(raw_repository).to receive(:list_refs).with(described_class::LFS_REF_PREFIXES).and_return(
        [ref('refs/heads/main', 'a1')],
        [ref('refs/heads/main', 'a1'), ref('refs/heads/new', 'a1')]
      )

      expect(service.execute[:lfs_revisions]).to eq(generation: 1, revisions: [])
    end

    it 'hands over a new ref as its tip when the default branch did not exist before the fetch' do
      allow(raw_repository).to receive(:list_refs).with(described_class::LFS_REF_PREFIXES).and_return(
        [ref('refs/heads/moved', 'b1')],
        [ref('refs/heads/main', 'a1'), ref('refs/heads/moved', 'b1')]
      )

      expect(service.execute[:lfs_revisions]).to eq(generation: 1, revisions: %w[a1])
    end

    it 'hands over every changed ref up to the limit' do
      refs_after = Array.new(described_class::MAX_LFS_REVISIONS) { |i| ref("refs/heads/branch-#{i}", "sha#{i}") }
      allow(raw_repository).to receive(:list_refs).and_return([], refs_after)

      expect(service.execute[:lfs_revisions][:revisions].size).to eq(described_class::MAX_LFS_REVISIONS)
    end

    it 'hands over a revision once when several new refs point at the same commit' do
      new_tags = Array.new(described_class::MAX_LFS_REVISIONS + 1) { |i| ref("refs/tags/v#{i}", 'd1') }
      allow(raw_repository).to receive(:list_refs).with(described_class::LFS_REF_PREFIXES).and_return(
        [ref('refs/heads/main', 'a1')],
        [ref('refs/heads/main', 'a1'), *new_tags]
      )

      expect(service.execute[:lfs_revisions]).to eq(generation: 1, revisions: %w[a1..d1])
    end

    it 'hands over no revisions when more refs changed than the LFS pass lists one by one' do
      refs_after = Array.new(described_class::MAX_LFS_REVISIONS + 1) { |i| ref("refs/heads/branch-#{i}", "sha#{i}") }
      allow(raw_repository).to receive(:list_refs).and_return([], refs_after)

      expect(service.execute[:lfs_revisions]).to eq(generation: 1, revisions: nil)
    end

    where(failing_call: [1, 2])

    with_them do
      it 'hands over no revisions when reading the refs fails, so the LFS pass scans every ref' do
        calls = 0
        allow(raw_repository).to receive(:list_refs) do
          calls += 1
          raise Gitlab::Git::CommandTimedOut, 'list refs timed out' if calls == failing_call

          []
        end

        expect(service.execute).to eq(
          applied_domains: %w[inventory source],
          follow_up: false,
          lfs_revisions: { generation: 1, revisions: nil }
        )
        expect(lfs_state.reload).to have_attributes(desired_generation: 1, state: 'pending')
      end
    end

    it 'asks for the LFS pass before the fetch, so a job that dies after the fetch still leaves one' do
      allow(git_repository).to receive(:fetch_as_mirror) do
        expect(lfs_state.reload).to have_attributes(desired_generation: 1, state: 'pending')
        fetch_result
      end

      service.execute

      expect(git_repository).to have_received(:fetch_as_mirror)
    end

    it 'keeps an interrupted LFS pass running' do
      lfs_state.update!(state: :running)

      service.execute

      expect(lfs_state.reload).to have_attributes(desired_generation: 1, state: 'running')
    end

    it 'asks for the LFS pass even when the pass fails after the fetch' do
      allow(git_repository).to receive(:fetch_as_mirror) do
        sync_repository.update!(application_generation: application_generation + 1)
        fetch_result
      end

      expect { service.execute }.to raise_error(Import::Sync::Errors::StaleApplicationError)

      expect(lfs_state.reload).to have_attributes(desired_generation: 1, state: 'pending')
    end

    it 'does not move a paused LFS domain to pending' do
      lfs_state.update!(state: :paused)

      service.execute

      expect(lfs_state.reload).to have_attributes(desired_generation: 1, state: 'paused')
    end
  end

  it 'asks for an LFS pass when the fetch fails, since it may have moved refs' do
    lfs_state
    allow(git_repository).to receive(:fetch_as_mirror).and_raise(Gitlab::Git::CommandError, 'fetch timed out')

    expect { service.execute }.to raise_error(Gitlab::Git::CommandError)

    expect(lfs_state.reload).to have_attributes(desired_generation: 1, state: 'pending')
    expect(source_state.reload).to have_attributes(synced_generation: 1, state: 'degraded')
  end

  context 'when the fetch changes nothing' do
    let(:fetch_result) { Gitaly::FetchRemoteResponse.new(repo_changed: false) }

    before do
      lfs_state
    end

    it 'asks for an LFS pass with nothing to scan' do
      expect(service.execute).to eq(
        applied_domains: %w[inventory source],
        follow_up: false,
        lfs_revisions: { generation: 1, revisions: [] }
      )

      expect(lfs_state.reload).to have_attributes(desired_generation: 1, state: 'pending')
      expect(raw_repository).to have_received(:list_refs).once
    end
  end

  it 'leaves a newer desired generation pending for a coalesced follow-up' do
    allow(git_repository).to receive(:fetch_as_mirror) do
      source_state.update!(desired_generation: 3)
      fetch_result
    end

    result = service.execute

    expect(result[:follow_up]).to be(true)
    expect(source_state.reload).to have_attributes(
      desired_generation: 3,
      synced_generation: 2,
      state: 'pending'
    )
    expect(source_state.synced_generation).to be <= source_state.desired_generation
  end

  it 'does not advance checkpoints and stores only sanitized health on failure' do
    allow(git_repository).to receive(:fetch_as_mirror).and_raise(StandardError, 'secret provider detail')

    expect(Gitlab::GithubImport::Logger).to receive(:warn).with(
      message: 'GitHub source reconciliation failed',
      import_sync_repository_id: sync_repository.id,
      Labkit::Fields::GL_PROJECT_ID => project.id,
      Labkit::Fields::ERROR_TYPE => 'StandardError',
      domain: anything,
      last_error_code: 'github_update_failed',
      health_state: 'degraded'
    ).twice

    expect { service.execute }.to raise_error(StandardError, 'secret provider detail')

    expect(inventory_state.reload).to have_attributes(
      synced_generation: 1,
      state: 'degraded',
      last_error_code: 'github_update_failed',
      last_error_message: 'GitHub update failed'
    )
    expect(source_state.reload).to have_attributes(
      synced_generation: 1,
      state: 'degraded',
      last_error_code: 'github_update_failed',
      last_error_message: 'GitHub update failed'
    )
  end

  it 'marks the running domains delayed, not degraded, and does not log a failure when GitHub rate limits the pass' do
    allow(git_repository).to receive(:fetch_as_mirror)
      .and_raise(Gitlab::GithubImport::RateLimitError.new('rate limited provider response', 90))
    expect(Gitlab::GithubImport::Logger).not_to receive(:warn)

    expect { service.execute }.to raise_error(Gitlab::GithubImport::RateLimitError)

    [inventory_state, source_state].each do |state|
      expect(state.reload).to have_attributes(
        synced_generation: 1,
        state: 'delayed',
        last_error_code: 'github_rate_limited',
        last_error_message: 'GitHub rate limit reached'
      )
    end
  end

  it 'propagates the original error when recording the failure itself fails' do
    allow(git_repository).to receive(:fetch_as_mirror).and_raise(StandardError, 'original failure')
    calls = 0
    allow(sync_repository).to receive(:sync_states_for_update).and_wrap_original do |original, *args|
      calls += 1
      calls <= 2 ? original.call(*args) : raise(ActiveRecord::StatementInvalid, 'recording failed')
    end
    expect(Gitlab::ErrorTracking).to receive(:track_exception)
      .with(instance_of(ActiveRecord::StatementInvalid), anything)

    expect { service.execute }.to raise_error(StandardError, 'original failure')
  end

  context 'when only the inventory domain is lagging' do
    before do
      source_state.update!(synced_generation: 2, state: :current)
    end

    it 'updates the identity without fetching refs' do
      expect(service.execute).to eq(applied_domains: %w[inventory], follow_up: false)

      expect(git_repository).not_to have_received(:fetch_as_mirror)
      expect(sync_repository.reload.provider_full_name).to eq('example/renamed')
      expect(inventory_state.reload).to have_attributes(synced_generation: 2, state: 'current')
      expect(source_state.reload).to have_attributes(synced_generation: 2, state: 'current')
    end

    it 'degrades only the running domain when the pass fails' do
      allow(client).to receive(:repository).and_raise(StandardError, 'provider unavailable')

      expect { service.execute }.to raise_error(StandardError, 'provider unavailable')

      expect(inventory_state.reload).to have_attributes(state: 'degraded', synced_generation: 1)
      expect(source_state.reload).to have_attributes(state: 'current', last_error_code: nil)
    end
  end

  context 'when HEAD already points at the GitHub default branch' do
    before do
      allow(raw_repository).to receive(:root_ref).with(head_only: true).and_return('main')
    end

    it 'does not rewrite HEAD, so no default branch change is published' do
      service.execute

      expect(git_repository).to have_received(:fetch_as_mirror)
      expect(git_repository).not_to have_received(:change_head)
      expect(source_state.reload).to have_attributes(state: 'current', synced_generation: 2)
    end

    it 'logs a Geo updated event so secondaries pick up the fetched commits' do
      service.execute

      expect(git_repository).to have_received(:log_geo_updated_event).once
    end
  end

  context 'when the GitHub default branch differs from HEAD' do
    before do
      allow(raw_repository).to receive(:root_ref).with(head_only: true).and_return('master')
    end

    it 'moves HEAD to the GitHub default branch' do
      service.execute

      expect(git_repository).to have_received(:change_head).with('main').once
    end

    it 'leaves the Geo updated event to change_head' do
      service.execute

      expect(git_repository).not_to have_received(:log_geo_updated_event)
    end

    context 'when the GitHub default branch does not exist locally' do
      before do
        allow(git_repository).to receive(:change_head).and_return(false)
      end

      it 'logs the Geo updated event itself, since change_head did not' do
        service.execute

        expect(git_repository).to have_received(:log_geo_updated_event).once
      end
    end
  end

  it 'does not move HEAD when GitHub reports no default branch' do
    provider_repository[:default_branch] = nil

    service.execute

    expect(git_repository).to have_received(:fetch_as_mirror)
    expect(git_repository).not_to have_received(:change_head)
    expect(git_repository).to have_received(:log_geo_updated_event).once
    expect(sync_repository.reload.provider_default_branch).to be_nil
  end

  it 'rejects a repository response with a different node ID' do
    provider_repository[:node_id] = 'R_other'

    expect { service.execute }
      .to raise_error(Import::Sync::Errors::ProviderIdentityError, /did not match/)

    expect(git_repository).not_to have_received(:fetch_as_mirror)
    expect(sync_repository.reload.provider_repository_node_id).not_to eq('R_other')
  end

  it 'rejects a repository response with a different stable provider ID' do
    provider_repository[:id] = 456

    expect { service.execute }
      .to raise_error(Import::Sync::Errors::ProviderIdentityError, /did not match/)

    expect(git_repository).not_to have_received(:fetch_as_mirror)
    expect(source_state.reload.synced_generation).to eq(1)
  end

  it 'does not mutate provider identity or refs when the application generation changes after the read' do
    original_full_name = sync_repository.provider_full_name
    allow(client).to receive(:repository) do
      sync_repository.update!(application_generation: application_generation + 1)
      provider_repository
    end

    expect { service.execute }
      .to raise_error(Import::Sync::Errors::StaleApplicationError, /generation changed/)

    expect(sync_repository.reload.provider_full_name).to eq(original_full_name)
    expect(git_repository).not_to have_received(:fetch_as_mirror)
    expect(source_state.reload.synced_generation).to eq(1)
  end

  it 'fetches no refs when the application generation changes between the fence and the fetch' do
    allow(service).to receive(:apply_provider_identity).and_wrap_original do |original, *args|
      original.call(*args)
      sync_repository.update!(application_generation: application_generation + 1)
    end

    expect { service.execute }
      .to raise_error(Import::Sync::Errors::StaleApplicationError, /generation changed/)

    expect(git_repository).not_to have_received(:fetch_as_mirror)
    expect(git_repository).not_to have_received(:change_head)
    expect(source_state.reload.synced_generation).to eq(1)
  end

  it 'does not move HEAD when the application generation changes during the fetch' do
    allow(git_repository).to receive(:fetch_as_mirror) do
      sync_repository.update!(application_generation: application_generation + 1)
      fetch_result
    end

    expect { service.execute }
      .to raise_error(Import::Sync::Errors::StaleApplicationError, /generation changed/)

    expect(git_repository).to have_received(:expire_all_method_caches)
    expect(git_repository).not_to have_received(:change_head)
    expect(project).not_to have_received(:touch)
    expect(source_state.reload).to have_attributes(synced_generation: 1, state: 'degraded')
  end

  it 'does not advance the generation when the application generation changes after HEAD moved' do
    allow(project).to receive(:touch) do
      sync_repository.update!(application_generation: application_generation + 1)
    end

    expect { service.execute }
      .to raise_error(Import::Sync::Errors::StaleApplicationError, /while provider state was being applied/)

    expect(git_repository).to have_received(:change_head)
    expect(inventory_state.reload).to have_attributes(synced_generation: 1, state: 'degraded')
    expect(source_state.reload).to have_attributes(synced_generation: 1, state: 'degraded')
  end

  it 'verifies the lease immediately before the fetch' do
    calls = []
    allow(lease_context).to receive(:verify!) { calls << :verify }
    allow(git_repository).to receive(:fetch_as_mirror) do
      calls << :fetch_as_mirror
      fetch_result
    end

    service.execute

    expect(calls.each_cons(2)).to include(%i[verify fetch_as_mirror])
  end

  it 'pauses instead of degrading when authority left provider_canonical during the pass' do
    allow(client).to receive(:repository) do
      sync_repository.update!(authority_state: :gitlab_canonical)
      provider_repository
    end

    expect { service.execute }.to raise_error(Import::Sync::Errors::StaleApplicationError)

    expect(source_state.reload).to have_attributes(
      state: 'paused',
      last_error_code: 'github_updates_inactive',
      last_error_message: 'GitHub updates are not active',
      synced_generation: 1
    )
  end

  it 'does not apply provider state after updates have stopped' do
    sync_repository.update!(authority_state: :gitlab_canonical)

    expect(service.execute).to eq(applied_domains: [], follow_up: false)
    expect(client).not_to have_received(:repository)
    expect(git_repository).not_to have_received(:fetch_as_mirror)
  end

  it 'runs the final pass for a cutting_over row when allow_cutover is true' do
    sync_repository.update!(authority_state: :cutting_over)
    final_service = described_class.new(
      sync_repository,
      application_generation: application_generation,
      allow_cutover: true,
      now: -> { current_time }
    )

    expect(final_service.execute(lease_context: lease_context))
      .to eq(applied_domains: %w[inventory source], follow_up: false, lfs_revisions: { generation: 2, revisions: [] })

    expect(git_repository).to have_received(:fetch_as_mirror)
    expect([inventory_state, source_state].map { |state| state.reload.synced_generation }).to eq([2, 2])
  end

  it 'does nothing for a cutting_over row when allow_cutover is false' do
    sync_repository.update!(authority_state: :cutting_over)

    expect(service.execute(lease_context: lease_context)).to eq(applied_domains: [], follow_up: false)

    expect(client).not_to have_received(:repository)
    expect(git_repository).not_to have_received(:fetch_as_mirror)
    expect([inventory_state, source_state].map { |state| state.reload.synced_generation }).to eq([1, 1])
  end

  it 'records a degraded state when credentials are missing' do
    allow(authentication).to receive(:client)
      .and_raise(Import::Sync::Errors::MissingCredentialsError, 'Project import data is missing')

    expect { service.execute }.to raise_error(Import::Sync::Errors::MissingCredentialsError)

    expect(source_state.reload).to have_attributes(state: 'degraded', synced_generation: 1)
  end

  context 'when the lease is lost' do
    it 'writes no state when it is lost before the pass starts' do
      allow(lease_context).to receive(:verify_repository!)
        .and_raise(Import::Sync::Repositories::ApplicationLease::LostLeaseError)

      expect { service.execute(lease_context: lease_context) }
        .to raise_error(Import::Sync::Repositories::ApplicationLease::LostLeaseError)

      expect(inventory_state.reload).to have_attributes(state: 'pending', synced_generation: 1)
      expect(source_state.reload).to have_attributes(state: 'pending', synced_generation: 1)
    end

    it 'writes no provider identity, refs or health when it is lost at the fence' do
      allow(lease_context).to receive(:verify!)
        .and_raise(Import::Sync::Repositories::ApplicationLease::LostLeaseError)
      original_full_name = sync_repository.provider_full_name

      expect { service.execute }
        .to raise_error(Import::Sync::Repositories::ApplicationLease::LostLeaseError)

      expect(sync_repository.reload.provider_full_name).to eq(original_full_name)
      expect(git_repository).not_to have_received(:fetch_as_mirror)
      expect(source_state.reload).to have_attributes(state: 'running', last_error_code: nil, synced_generation: 1)
    end

    it 'does not advance the generation when it is lost after the fetch' do
      allow(lease_context).to receive(:renew!)
        .and_return(true)
        .and_raise(Import::Sync::Repositories::ApplicationLease::LostLeaseError)

      expect { service.execute }
        .to raise_error(Import::Sync::Repositories::ApplicationLease::LostLeaseError)

      expect(git_repository).not_to have_received(:change_head)
      expect(source_state.reload).to have_attributes(synced_generation: 1, last_error_code: nil)
    end

    it 'does not advance the generation when it is lost before the final write' do
      verify_calls = 0
      allow(lease_context).to receive(:verify!) do
        verify_calls += 1
        raise Import::Sync::Repositories::ApplicationLease::LostLeaseError if verify_calls == 4
      end

      expect { service.execute }
        .to raise_error(Import::Sync::Repositories::ApplicationLease::LostLeaseError)

      expect(git_repository).to have_received(:change_head)
      expect(inventory_state.reload.synced_generation).to eq(1)
      expect(source_state.reload).to have_attributes(synced_generation: 1, state: 'running')
    end
  end

  context 'with a real repository' do
    let(:user) { create(:user) }
    let(:sync_repository) do
      create(
        :import_sync_repository,
        :oauth,
        project: create(:project, :repository),
        authority_state: :provider_canonical,
        provider_repository_xid: 123
      )
    end

    let(:provider_repository) do
      { id: 123, node_id: sync_repository.provider_repository_node_id, full_name: 'example/renamed',
        default_branch: 'master' }
    end

    let(:old_pointer) { Gitlab::Git::LfsPointerFile.new('old') }
    let(:moved_pointer) { Gitlab::Git::LfsPointerFile.new('moved') }
    let(:branch_pointer) { Gitlab::Git::LfsPointerFile.new('branch') }

    before do
      stub_lfs_setting(enabled: true)
      allow(project).to receive(:repository).and_call_original
      allow(project).to receive(:default_branch).and_call_original
    end

    it 'hands over revisions that list only the LFS pointers the fetch added' do
      repository = project.repository
      commit_pointer(old_pointer, 'old.bin', 'master')
      master_before = repository.commit('master').sha

      allow(repository).to receive(:fetch_as_mirror) do
        commit_pointer(moved_pointer, 'moved.bin', 'master')
        repository.add_branch(user, 'lfs-branch', master_before)
        commit_pointer(branch_pointer, 'branch.bin', 'lfs-branch')
        repository.add_tag(user, 'v-lfs', 'lfs-branch')
        fetch_result
      end

      revisions = service.execute[:lfs_revisions][:revisions]
      pointers = Projects::LfsPointers::LfsListService.new(project, nil, updated_revisions: revisions).execute

      branch_sha = repository.commit('lfs-branch').sha
      expect(revisions).to contain_exactly(
        "#{master_before}..#{repository.commit('master').sha}",
        "#{master_before}..#{branch_sha}"
      )
      expect(pointers.keys).to include(moved_pointer.sha256, branch_pointer.sha256)
      expect(pointers.keys).not_to include(old_pointer.sha256)
    end

    def commit_pointer(pointer, path, branch)
      project.repository.create_file(user, path, pointer.pointer, message: "Add #{path}", branch_name: branch)
    end
  end

  def ref(name, target)
    Gitaly::ListRefsResponse::Reference.new(name: name, target: target)
  end
end
