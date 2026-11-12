# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Gitlab::GithubImport::Importer::ReleasesImporter, :clean_gitlab_redis_shared_state, feature_category: :importers do
  let_it_be_with_reload(:project) { create(:project, :github_import, :in_group) }

  let(:client) { instance_double(Gitlab::GithubImport::Client, web_endpoint: 'https://github.com') }
  let(:updated_at) { Time.utc(2026, 10, 20, 12) }
  let(:continuous_sync) { true }
  let(:github_releases) do
    [
      { id: 123, tag_name: 'v1.0', name: 'One', body: 'First', created_at: updated_at, published_at: updated_at,
        updated_at: updated_at, author: nil },
      { id: 124, tag_name: 'v2.0', name: 'Two', body: 'Second', created_at: updated_at, published_at: updated_at,
        updated_at: updated_at + 1.hour, author: nil }
    ]
  end

  subject(:importer) { described_class.new(project, client) }

  before do
    project.build_or_assign_import_data(data: { 'optional_stages' => { 'continuous_sync' => continuous_sync } }).save!
    allow(importer).to receive(:each_release).and_return(github_releases)
  end

  context 'with a provisioning sync repository' do
    let_it_be_with_reload(:repository) { create(:import_sync_repository, :oauth, project: project) }

    it 'maps the imported releases' do
      expect { importer.execute }.to change { Import::Sync::ExternalObject.count }.by(2)

      expect(Import::Sync::ExternalObject.releases_of(repository: repository).map do |mapping|
        [mapping.provider_object_xid, mapping.release.tag, mapping.provider_updated_at]
      end).to contain_exactly([123, 'v1.0', updated_at], [124, 'v2.0', updated_at + 1.hour])
    end

    it 'does not map a release whose tag existed before the import' do
      create(:release, project: project, tag: 'v1.0')

      expect { importer.execute }.to change { Import::Sync::ExternalObject.count }.by(1)
      expect(Import::Sync::ExternalObject.last.release.tag).to eq('v2.0')
    end

    it 'does not map a release without a GitHub id' do
      github_releases.last[:id] = nil

      expect { importer.execute }.to change { Release.count }.by(2)
        .and change { Import::Sync::ExternalObject.count }.by(1)
    end

    it 'writes no mapping when no release has a GitHub id' do
      github_releases.each { |release| release[:id] = nil }

      expect(Import::Sync::ExternalObject).not_to receive(:insert_all)
      expect { importer.execute }.to change { Release.count }.by(2)
    end

    it 'maps a release without an update time' do
      github_releases.first[:updated_at] = nil

      importer.execute

      mapping = Import::Sync::ExternalObject.for_provider(repository: repository, kind: :release,
        provider_object_xid: 123)
      expect(mapping).to have_attributes(provider_updated_at: nil)
    end

    it 'rolls the releases back when a mapping cannot be written' do
      allow(Import::Sync::ExternalObject).to receive(:insert_all).and_raise(ActiveRecord::StatementInvalid)

      expect { importer.execute }.to raise_error(ActiveRecord::StatementInvalid)
        .and not_change { Release.count }
    end

    it 'keeps the batches written before a mapping fails' do
      github_releases.replace(Array.new(101) do |index|
        { id: 200 + index, tag_name: "v#{index}", name: "Release #{index}", body: 'Body', created_at: updated_at,
          published_at: updated_at, updated_at: updated_at, author: nil }
      end)
      calls = 0
      allow(Import::Sync::ExternalObject).to receive(:insert_all).and_wrap_original do |method, *args|
        calls += 1
        raise ActiveRecord::StatementInvalid if calls == 2

        method.call(*args)
      end

      expect { importer.execute }.to raise_error(ActiveRecord::StatementInvalid)
        .and change { Release.count }.by(100)
        .and change { Import::Sync::ExternalObject.releases_of(repository: repository).count }.by(100)
    end

    context 'when continuous sync is disabled for the import' do
      let(:continuous_sync) { false }

      it 'writes no mapping' do
        expect { importer.execute }.to change { Release.count }.by(2)
          .and not_change { Import::Sync::ExternalObject.count }
      end
    end

    context 'when the repository is provider_canonical' do
      before do
        repository.update!(authority_state: :provider_canonical)
      end

      it 'writes no mapping' do
        expect { importer.execute }.to change { Release.count }.by(2)
          .and not_change { Import::Sync::ExternalObject.count }
      end
    end
  end

  context 'without a sync repository' do
    it 'imports the releases without a mapping' do
      expect { importer.execute }.to change { Release.count }.by(2)
        .and not_change { Import::Sync::ExternalObject.count }
    end
  end
end
