# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Import::Sync::Repositories::ReconcileLfsService, feature_category: :importers do
  let(:sync_repository) { create(:import_sync_repository, :oauth, authority_state: :provider_canonical) }
  let(:project) { sync_repository.project }
  let(:application_generation) { sync_repository.application_generation }
  let(:authentication) { instance_double(Import::Sync::Repositories::Authentication) }
  let(:lease) { instance_double(Import::Sync::Repositories::ApplicationLease) }
  let(:lease_context) do
    instance_double(
      Import::Sync::Repositories::ApplicationLease::Context,
      verify!: true,
      verify_repository!: true,
      renew!: true
    )
  end

  let(:lfs_objects_service) { instance_double(Import::Sync::Repositories::ReconcileLfsObjectsService, execute: true) }
  let(:current_time) { Time.zone.parse('2026-10-29 13:00:00') }
  let!(:lfs_state) do
    create(:import_sync_repository_state, repository: sync_repository, domain: :lfs, desired_generation: 2,
      synced_generation: 1)
  end

  let!(:source_state) do
    create(:import_sync_repository_state, repository: sync_repository, domain: :source, desired_generation: 2,
      synced_generation: 1)
  end

  subject(:service) do
    described_class.new(sync_repository, application_generation: application_generation, now: -> { current_time })
  end

  before do
    allow(Import::Sync::Repositories::ApplicationLease).to receive(:new).and_return(lease)
    allow(lease).to receive(:execute).and_yield(lease_context)
    allow(Import::Sync::Repositories::Authentication).to receive(:for).with(sync_repository).and_return(authentication)
    allow(Import::Sync::Repositories::ReconcileLfsObjectsService).to receive(:new)
      .with(project, authentication: authentication, lease_context: lease_context, revisions: nil)
      .and_return(lfs_objects_service)
  end

  it 'downloads the missing LFS objects and advances only the LFS domain' do
    expect(service.execute).to eq(applied_domains: %w[lfs], follow_up: false)

    expect(lfs_objects_service).to have_received(:execute)
    expect(lfs_state.reload).to have_attributes(
      synced_generation: 2,
      state: 'current',
      last_sync_started_at: current_time,
      last_successful_sync_at: current_time
    )
    expect(source_state.reload).to have_attributes(synced_generation: 1, state: 'pending')
  end

  it 'does nothing when the LFS domain is not lagging' do
    lfs_state.update!(synced_generation: 2, state: :current)

    expect(service.execute).to eq(applied_domains: [], follow_up: false)

    expect(Import::Sync::Repositories::ReconcileLfsObjectsService).not_to have_received(:new)
  end

  it 'asks for a follow-up when a newer generation arrives during the pass' do
    allow(lfs_objects_service).to receive(:execute) do
      lfs_state.update!(desired_generation: 3)
      true
    end

    expect(service.execute).to eq(applied_domains: %w[lfs], follow_up: true)

    expect(lfs_state.reload).to have_attributes(synced_generation: 2, state: 'pending')
  end

  context 'when the source pass hands over the revisions its fetch changed' do
    let(:lfs_revisions) { { generation: 2, revisions: %w[a1..a2 b1] } }

    subject(:service) do
      described_class.new(
        sync_repository,
        application_generation: application_generation,
        now: -> { current_time },
        lfs_revisions: lfs_revisions
      )
    end

    before do
      allow(Import::Sync::Repositories::ReconcileLfsObjectsService).to receive(:new)
        .with(project, authentication: authentication, lease_context: lease_context, revisions: %w[a1..a2 b1])
        .and_return(lfs_objects_service)
    end

    it 'lists only the pointers those revisions add when they are the only request left' do
      expect(service.execute).to eq(applied_domains: %w[lfs], follow_up: false)

      expect(Import::Sync::Repositories::ReconcileLfsObjectsService).to have_received(:new)
        .with(project, authentication: authentication, lease_context: lease_context, revisions: %w[a1..a2 b1])
      expect(lfs_state.reload).to have_attributes(synced_generation: 2, state: 'current')
    end

    it 'scans every ref when an earlier request was not applied' do
      lfs_state.update!(synced_generation: 0)

      service.execute

      expect(Import::Sync::Repositories::ReconcileLfsObjectsService).to have_received(:new)
        .with(project, authentication: authentication, lease_context: lease_context, revisions: nil)
    end

    it 'scans every ref when the revisions are for another generation' do
      lfs_state.update!(desired_generation: 3, synced_generation: 2)

      service.execute

      expect(Import::Sync::Repositories::ReconcileLfsObjectsService).to have_received(:new)
        .with(project, authentication: authentication, lease_context: lease_context, revisions: nil)
    end

    context 'when too many refs changed to list them' do
      let(:lfs_revisions) { { generation: 2, revisions: nil } }

      it 'scans every ref' do
        expect(service.execute).to eq(applied_domains: %w[lfs], follow_up: false)

        expect(Import::Sync::Repositories::ReconcileLfsObjectsService).to have_received(:new)
          .with(project, authentication: authentication, lease_context: lease_context, revisions: nil)
      end
    end
  end

  context 'when the LFS page is incomplete' do
    before do
      allow(lfs_objects_service).to receive(:execute).and_return(false)
    end

    it 'asks for another pass and leaves only the LFS domain lagging' do
      expect(service.execute).to eq(applied_domains: [], follow_up: true)

      expect(lfs_state.reload).to have_attributes(synced_generation: 1, state: 'running', last_error_code: nil)
      expect(source_state.reload).to have_attributes(synced_generation: 1, state: 'pending')
    end

    it 'advances the LFS domain once a later pass downloads the last page' do
      service.execute
      allow(lfs_objects_service).to receive(:execute).and_return(true)

      expect(service.execute).to eq(applied_domains: %w[lfs], follow_up: false)

      expect(lfs_state.reload).to have_attributes(synced_generation: 2, state: 'current')
    end
  end

  it 'degrades only the LFS domain when LFS reconciliation fails' do
    allow(lfs_objects_service).to receive(:execute)
      .and_raise(Import::Sync::Errors::LfsReconciliationError, 'GitHub LFS update failed')

    expect(Gitlab::GithubImport::Logger).to receive(:warn).with(
      message: 'GitHub LFS reconciliation failed',
      import_sync_repository_id: sync_repository.id,
      Labkit::Fields::GL_PROJECT_ID => project.id,
      Labkit::Fields::ERROR_TYPE => 'Import::Sync::Errors::LfsReconciliationError',
      domain: 'lfs',
      last_error_code: 'github_lfs_update_failed',
      health_state: 'degraded'
    )

    expect { service.execute }.to raise_error(Import::Sync::Errors::LfsReconciliationError)

    expect(lfs_state.reload).to have_attributes(
      synced_generation: 1,
      state: 'degraded',
      last_error_code: 'github_lfs_update_failed',
      last_error_message: 'GitHub LFS update failed'
    )
    expect(source_state.reload).to have_attributes(state: 'pending', last_error_code: nil)
  end

  it 'leaves the LFS domain alone when it stopped running before the failure' do
    allow(lfs_objects_service).to receive(:execute) do
      lfs_state.update!(state: :paused)
      raise Import::Sync::Errors::LfsReconciliationError, 'GitHub LFS update failed'
    end

    expect(Gitlab::GithubImport::Logger).not_to receive(:warn)

    expect { service.execute }.to raise_error(Import::Sync::Errors::LfsReconciliationError)

    expect(lfs_state.reload).to have_attributes(synced_generation: 1, state: 'paused', last_error_code: nil)
  end

  it 'downloads nothing when the application generation changed before the downloads' do
    allow(lease_context).to receive(:verify!) do
      sync_repository.update!(application_generation: application_generation + 1)
    end

    expect { service.execute }.to raise_error(Import::Sync::Errors::StaleApplicationError)

    expect(Import::Sync::Repositories::ReconcileLfsObjectsService).not_to have_received(:new)
    expect(lfs_state.reload).to have_attributes(synced_generation: 1, state: 'degraded')
  end

  it 'does not advance the generation when the application generation changes during the downloads' do
    allow(lfs_objects_service).to receive(:execute) do
      sync_repository.update!(application_generation: application_generation + 1)
      true
    end

    expect { service.execute }
      .to raise_error(Import::Sync::Errors::StaleApplicationError, /while LFS objects were being applied/)

    expect(lfs_state.reload).to have_attributes(synced_generation: 1, state: 'degraded')
  end

  it 'writes no state when the lease is lost during the downloads' do
    allow(lfs_objects_service).to receive(:execute)
      .and_raise(Import::Sync::Repositories::ApplicationLease::LostLeaseError)

    expect { service.execute }.to raise_error(Import::Sync::Repositories::ApplicationLease::LostLeaseError)

    expect(lfs_state.reload).to have_attributes(synced_generation: 1, state: 'running', last_error_code: nil)
  end

  it 'does nothing for a cutting_over row when allow_cutover is false' do
    sync_repository.update!(authority_state: :cutting_over)

    expect(service.execute(lease_context: lease_context)).to eq(applied_domains: [], follow_up: false)

    expect(Import::Sync::Repositories::ReconcileLfsObjectsService).not_to have_received(:new)
  end

  context 'when it is the final pass of a stop' do
    subject(:service) do
      described_class.new(
        sync_repository,
        application_generation: application_generation,
        allow_cutover: true,
        now: -> { current_time }
      )
    end

    before do
      sync_repository.update!(authority_state: :cutting_over)
    end

    it 'logs an LFS failure and finishes the pass without the missing objects' do
      allow(lfs_objects_service).to receive(:execute)
        .and_raise(Import::Sync::Errors::LfsReconciliationError, 'GitHub LFS update failed')

      expect(Gitlab::GithubImport::Logger).to receive(:warn).with(
        message: 'GitHub LFS update failed, finishing the stop without the missing LFS objects',
        import_sync_repository_id: sync_repository.id,
        Labkit::Fields::GL_PROJECT_ID => project.id
      )

      expect(service.execute(lease_context: lease_context)).to eq(applied_domains: %w[lfs], follow_up: false)

      expect(lfs_state.reload).to have_attributes(synced_generation: 2, state: 'current')
    end

    it 'still fails on other errors' do
      allow(lfs_objects_service).to receive(:execute)
        .and_raise(Import::Sync::Errors::MissingCredentialsError, 'Project import data is missing')

      expect { service.execute(lease_context: lease_context) }
        .to raise_error(Import::Sync::Errors::MissingCredentialsError)

      expect(lfs_state.reload).to have_attributes(synced_generation: 1, state: 'degraded')
    end
  end
end
