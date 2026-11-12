# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Import::Sync::Repositories::WorkItems::RemoveDeletedReleasesService, feature_category: :importers do
  let(:repository) { create(:import_sync_repository, :oauth, provider_full_name: 'example/connected') }

  let!(:kept_mapping) do
    create(:import_sync_external_object, :release, repository: repository, provider_object_xid: 201)
  end

  let!(:deleted_mapping) do
    create(:import_sync_external_object, :release, repository: repository, provider_object_xid: 202)
  end

  let(:client) { instance_double(Gitlab::GithubImport::Client) }
  let(:lease_context) do
    instance_double(Import::Sync::Repositories::ApplicationLease::Context, renew!: true, verify!: true)
  end

  let(:listed_releases) { [{ id: 201 }] }

  subject(:execute) { described_class.new(repository, client: client, lease_context: lease_context).execute }

  before do
    allow(client).to receive(:each_page)
      .with(:releases, nil, 'example/connected')
      .and_yield(Gitlab::GithubImport::Client::Page.new(listed_releases, nil))
    allow(client).to receive(:release).with('example/connected', 202).and_raise(Octokit::NotFound)
  end

  it 'removes a release deleted on GitHub and keeps the others', :aggregate_failures do
    deleted_release = deleted_mapping.release

    expect(Gitlab::GithubImport::Logger).to receive(:info).with(
      hash_including(message: 'removed GitHub release deleted on GitHub', release_id: deleted_release.id,
        provider_object_xid: 202)
    )

    execute

    expect(Release.exists?(deleted_release.id)).to be(false)
    expect(Import::Sync::ExternalObject.exists?(deleted_mapping.id)).to be(false)
    expect(kept_mapping.reload.release).to be_present
    expect(client).not_to have_received(:release).with('example/connected', 201)
    expect(lease_context).to have_received(:verify!)
  end

  it 'skips a release removed while GitHub was checked' do
    allow(client).to receive(:release).with('example/connected', 202) do
      deleted_mapping.release.delete
      raise Octokit::NotFound
    end

    expect(Gitlab::GithubImport::Logger).not_to receive(:info)

    expect { execute }.not_to raise_error
  end

  it 'keeps a release listed only on a later page' do
    allow(client).to receive(:each_page)
      .with(:releases, nil, 'example/connected')
      .and_yield(Gitlab::GithubImport::Client::Page.new(listed_releases, nil))
      .and_yield(Gitlab::GithubImport::Client::Page.new([{ id: 202 }], nil))

    expect { execute }.not_to change { Release.count }
    expect(client).not_to have_received(:release)
  end

  it 'keeps the release when the lease is lost before removing it' do
    allow(lease_context).to receive(:verify!)
      .and_raise(Import::Sync::Repositories::ApplicationLease::LostLeaseError, 'lost')

    expect { execute }.to raise_error(Import::Sync::Repositories::ApplicationLease::LostLeaseError, 'lost')
    expect(deleted_mapping.reload.release).to be_present
  end

  where(:error) { [Octokit::Forbidden, Octokit::ServerError] }

  with_them do
    it 'keeps the release and raises when GitHub fails to answer' do
      allow(client).to receive(:release).with('example/connected', 202).and_raise(error)

      expect { execute }.to raise_error(error)
      expect(deleted_mapping.reload.release).to be_present
    end
  end

  it 'keeps a release that GitHub still returns' do
    allow(client).to receive(:release).with('example/connected', 202).and_return({ id: 202 })

    expect { execute }.not_to change { Release.count }
  end

  it 'does not list GitHub releases when none are mapped' do
    Import::Sync::ExternalObject.delete_all

    execute

    expect(client).not_to have_received(:each_page)
  end

  it 'leaves releases of another repository alone' do
    other_mapping = create(:import_sync_external_object, :release, provider_object_xid: 203)

    execute

    expect(other_mapping.reload.release).to be_present
    expect(client).not_to have_received(:release).with('example/connected', 203)
  end
end
