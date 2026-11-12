# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Import::Sync::Repositories::WorkItems::ReconcileReleaseService,
  :clean_gitlab_redis_shared_state, feature_category: :importers do
  include Import::UserMappingHelper

  let_it_be_with_reload(:project) { create(:project, :in_group, :github_import, :import_user_mapping_enabled) }
  let_it_be(:source_user) { generate_source_user(project, 1) }
  let_it_be_with_reload(:repository) { create(:import_sync_repository, :oauth, project: project) }

  let(:client) { instance_double(Gitlab::GithubImport::Client, web_endpoint: 'https://github.com') }
  let(:fence) { instance_spy(Import::Sync::Repositories::ApplicationLease::Context) }
  let(:updated_at) { Time.zone.parse('2026-10-20 12:00:00') }
  let(:published_at) { Time.zone.parse('2026-10-19 12:00:00') }
  let(:provider_release) do
    {
      id: 123,
      tag_name: 'v1.0',
      name: 'First release',
      body: 'Release notes',
      created_at: Time.zone.parse('2026-10-18 12:00:00'),
      published_at: published_at,
      updated_at: updated_at,
      author: { id: 1, login: 'alice' }
    }
  end

  subject(:service) { described_class.new(repository, client: client, verify_fence: -> { fence.verify! }) }

  def mapping
    Import::Sync::ExternalObject.for_provider(repository: repository, kind: :release, provider_object_xid: 123)
  end

  def map_release(release, provider_updated_at: updated_at - 1.day)
    create(:import_sync_external_object, :release, repository: repository, provider_object_xid: 123,
      release: release, provider_updated_at: provider_updated_at)
  end

  context 'when the release is new' do
    it 'creates the release and maps it at the GitHub version' do
      release = nil

      expect { release = service.execute(provider_release) }.to change { project.releases.count }.by(1)

      expect(release).to have_attributes(
        tag: 'v1.0',
        name: 'First release',
        description: 'Release notes',
        released_at: published_at,
        author_id: source_user.mapped_user_id
      )
      expect(mapping).to have_attributes(release: release, provider_updated_at: updated_at)
      expect(fence).to have_received(:verify!).twice
    end

    it 'pushes a placeholder reference for the author' do
      allow(Import::DirectReassignService).to receive(:supported?).and_return(false)

      release = service.execute(provider_release)

      expect(placeholder_user_references(::Import::SOURCE_GITHUB, project.import_state.id)).to contain_exactly(
        ['Release', release.id, 'author_id', source_user.id]
      )
    end

    it 'keeps the unversioned mapping when a later step fails' do
      allow(fence).to receive(:verify!).and_invoke(-> {}, -> { raise StandardError })

      expect { service.execute(provider_release) }.to raise_error(StandardError)

      expect(mapping).to have_attributes(release: project.releases.find_by(tag: 'v1.0'), provider_updated_at: nil)
    end

    it 'creates a draft with the current time as its release date' do
      freeze_time do
        release = service.execute(provider_release.merge(published_at: nil))

        expect(release.released_at).to eq(Time.current)
        expect(mapping).to have_attributes(release: release, provider_updated_at: updated_at)
      end
    end
  end

  context 'when the release is mapped' do
    let!(:release) do
      create(:release, project: project, tag: 'v0.9', name: 'Old name', description: 'Old notes',
        released_at: published_at - 1.day)
    end

    before do
      map_release(release)
    end

    it 'updates the release from GitHub' do
      expect { service.execute(provider_release) }.not_to change { project.releases.count }

      expect(release.reload).to have_attributes(
        tag: 'v1.0',
        name: 'First release',
        description: 'Release notes',
        released_at: published_at
      )
      expect(mapping.provider_updated_at).to eq(updated_at)
    end

    it 'does not look up the release author' do
      expect(Gitlab::GithubImport::UserFinder).not_to receive(:new)

      service.execute(provider_release)
    end

    it 'keeps the release date of a draft' do
      service.execute(provider_release.merge(published_at: nil))

      expect(release.reload.released_at).to eq(published_at - 1.day)
    end

    it 'skips a release whose version is already applied' do
      mapping.update!(provider_updated_at: updated_at)

      expect(service.execute(provider_release)).to be_nil
      expect(release.reload.name).to eq('Old name')
      expect(fence).not_to have_received(:verify!)
    end

    it 'skips a release that GitHub lists at an older version than the mapping' do
      mapping.update!(provider_updated_at: updated_at + 1.hour)

      expect(service.execute(provider_release)).to be_nil
      expect(release.reload.name).to eq('Old name')
      expect(mapping.provider_updated_at).to eq(updated_at + 1.hour)
    end

    it 'leaves the release alone when the lease is lost before the update' do
      allow(fence).to receive(:verify!)
        .and_raise(Import::Sync::Repositories::ApplicationLease::LostLeaseError, 'lost')

      expect { service.execute(provider_release) }
        .to raise_error(Import::Sync::Repositories::ApplicationLease::LostLeaseError, 'lost')
      expect(release.reload).to have_attributes(tag: 'v0.9', name: 'Old name')
      expect(mapping.provider_updated_at).to eq(updated_at - 1.day)
    end

    it 'skips a tag change onto a tag that another GitLab release has' do
      create(:release, project: project, tag: 'v1.0', name: 'GitLab release')

      expect(service.execute(provider_release)).to be_nil
      expect(release.reload).to have_attributes(tag: 'v0.9', name: 'Old name')
      expect(mapping.provider_updated_at).to eq(updated_at - 1.day)
    end

    it 'raises when the mapping points to another project' do
      release.update_column(:project_id, create(:project).id)

      expect { service.execute(provider_release) }
        .to raise_error(Import::Sync::Errors::MappingConflictError)
    end
  end

  it 'skips an unmapped GitLab release with the same tag' do
    existing = create(:release, project: project, tag: 'v1.0', name: 'GitLab release')

    expect(Gitlab::GithubImport::Logger).to receive(:warn).with(
      hash_including(
        message: 'skipping GitHub release whose tag belongs to another GitLab release',
        provider_object_xid: 123,
        release_id: existing.id
      )
    )

    expect(service.execute(provider_release)).to be_nil
    expect(existing.reload.name).to eq('GitLab release')
    expect(mapping).to be_nil
  end

  it 'skips a release without a tag' do
    expect { service.execute(provider_release.merge(tag_name: nil)) }.not_to change { Release.count }
  end

  it 'raises for a release without an identity' do
    expect { service.execute(provider_release.merge(id: nil)) }
      .to raise_error(Import::Sync::Errors::ProviderObjectError, 'GitHub object identity is invalid')
  end

  it 'raises for a release without an update time' do
    expect { service.execute(provider_release.merge(updated_at: nil)) }
      .to raise_error(Import::Sync::Errors::ProviderObjectError, 'GitHub object update time is invalid')
  end

  it 'raises for a release with an unreadable update time' do
    expect { service.execute(provider_release.merge(updated_at: '2026-13-45')) }
      .to raise_error(Import::Sync::Errors::ProviderObjectError, 'GitHub object update time is invalid')
  end

  it 'does not rewrite attachments when attachments import is off' do
    expect(Gitlab::GithubImport::Importer::NoteAttachmentsImporter).not_to receive(:new)

    service.execute(provider_release)
  end

  context 'when attachments are imported' do
    let(:attachments_importer) { instance_double(Gitlab::GithubImport::Importer::NoteAttachmentsImporter) }

    before do
      project.build_or_assign_import_data(data: { 'optional_stages' => { 'attachments_import' => true } }).save!
      allow(Gitlab::GithubImport::Importer::NoteAttachmentsImporter).to receive(:new).and_return(attachments_importer)
      allow(attachments_importer).to receive(:execute)
    end

    it 'rewrites the attachments in the release notes' do
      release = service.execute(provider_release)

      expect(Gitlab::GithubImport::Importer::NoteAttachmentsImporter).to have_received(:new).with(
        an_object_having_attributes(record_db_id: release.id, record_type: 'Release'), project, client
      )
      expect(attachments_importer).to have_received(:execute)
    end

    it 'finishes a release that a failed pass left unversioned' do
      allow(fence).to receive(:verify!).and_invoke(-> {}, -> { raise StandardError }, -> {})

      expect { service.execute(provider_release) }.to raise_error(StandardError)
      expect { service.execute(provider_release) }.not_to change { project.releases.count }

      expect(mapping).to have_attributes(
        release: project.releases.find_by(tag: 'v1.0'), provider_updated_at: updated_at
      )
      expect(attachments_importer).to have_received(:execute).twice
    end
  end
end
