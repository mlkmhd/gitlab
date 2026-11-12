# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Gitlab::OrgMover::Manifest, feature_category: :organization do
  describe '#generate' do
    # Generating reads every table's columns, so build the manifest once.
    let_it_be(:manifest) { described_class.new.generate }

    let(:databases) { manifest[:siphon][:databases] }
    let(:tables) { databases.values.flat_map { |database| database[:tables] } }
    let(:table_names) { tables.map { |table| table[:table] } }

    it 'describes the gitlab-rails service with a generation timestamp', :aggregate_failures do
      expect(manifest[:service]).to eq('gitlab-rails')
      expect(Time.iso8601(manifest[:generated_at])).to be_present
    end

    it 'files every table under a gitlab_-prefixed PostgreSQL database', :aggregate_failures do
      expect(databases.keys).to all(match(/\Agitlab_/))
      expect(databases.values).to all(include(type: 'SIPHON_DATABASE_TYPE_POSTGRESQL'))
    end

    it 'includes organization-owned tables with their live columns', :aggregate_failures do
      expect(table_names).to include('projects', 'users', 'issues')

      projects = tables.find { |table| table[:table] == 'projects' }
      expect(projects[:columns]).to include(a_hash_including(name: 'id'))
    end

    it 'keeps type modifiers and the [] of array column types', :aggregate_failures do
      namespaces = tables.find { |table| table[:table] == 'namespaces' }
      projects = tables.find { |table| table[:table] == 'projects' }

      expect(namespaces[:columns]).to include({ name: 'traversal_ids', type: 'bigint[]' })
      expect(projects[:columns]).to include({ name: 'suggestion_commit_message', type: 'character varying(255)' })
    end

    it 'reads the columns with one catalog query per connection' do
      # Rails names table_exists? and columns queries SCHEMA, so count those too.
      recorder = ActiveRecord::QueryRecorder.new(skip_schema_queries: false) { described_class.new.generate }

      connections = Gitlab::Database.all_database_connections.values.count do |connection|
        connection.gitlab_schemas.intersect?(described_class::MIGRATED_SCHEMAS.map(&:to_sym))
      end

      expect(recorder.count).to be <= connections
    end

    it 'only emits sharding keys graded to supported member tables', :aggregate_failures do
      tables.each do |table|
        expect(table[:sharding_key]).to be_present
        expect(table[:sharding_key].values).to all(be_in(described_class::SHARDING_KEYS.values))
      end
    end

    it 'leaves out excluded tables and non-migrated schemas', :aggregate_failures do
      expect(table_names).not_to include('lfs_objects_projects')
      expect(table_names).not_to include('application_settings')
    end

    it 'marks per-cell bot rows as ignored on the users table' do
      users = tables.find { |table| table[:table] == 'users' }

      expect(users[:ignore]).to match(/user_type IN \(\d+(,\d+)*\)/)
    end

    it 'maps asset sources to tables the manifest carries', :aggregate_failures do
      object_sources = manifest[:object_storage][:sources]
      gitaly_sources = manifest[:gitaly][:sources]

      expect(object_sources.map { |source| source[:database][:table] }).to all(be_in(table_names))
      expect(gitaly_sources.map { |source| source[:database][:table] }).to all(be_in(table_names))
      expect(gitaly_sources).to include(
        a_hash_including(handler: 'GITALY_HANDLER_REPOSITORY',
          database: a_hash_including(table: 'project_repositories'))
      )
      expect(manifest[:gitaly][:storages].keys)
        .to match_array(Gitlab.config.repositories.storages.keys.map(&:to_s))
    end

    it 'carries every table the handler maps name', :aggregate_failures do
      expect(described_class::OBJECT_STORAGE.keys - table_names).to be_empty
      expect(described_class::GITALY.keys - table_names).to be_empty
    end

    it 'names uploads sources with the uploads handler and storage', :aggregate_failures do
      uploads = manifest[:object_storage][:sources].find { |source| source[:database][:table] == 'project_uploads' }

      expect(uploads).to include(handler: 'OBJECT_STORAGE_HANDLER_UPLOADS', storage: 'uploads')
      expect(manifest[:object_storage][:storages]).to include('uploads' => {})
    end

    context 'when a migrated schema has no owning connection' do
      before do
        allow(Gitlab::Database).to receive(:all_database_connections).and_return({})
      end

      it 'raises rather than guessing a database' do
        expect { described_class.new.generate }.to raise_error(described_class::Error, /no Rails connection owns/)
      end
    end
  end

  describe '#generate with a fixed dictionary' do
    subject(:manifest) { described_class.new.generate }

    let(:databases) { manifest[:siphon][:databases] }
    let(:table_names) { databases.values.flat_map { |database| database[:tables] }.pluck(:table) }
    let(:entries) do
      [
        entry('projects', 'gitlab_main_org', { 'organization_id' => 'organizations' }),
        entry('project_repositories', 'gitlab_main_org', { 'project_id' => 'projects' }),
        entry('project_uploads', 'gitlab_main_org', { 'project_id' => 'projects' }),
        entry('merge_request_diffs', 'gitlab_main_org', { 'project_id' => 'merge_requests' }),
        entry('issues', 'gitlab_main_org', nil),
        entry('lfs_objects_projects', 'gitlab_main_org', { 'project_id' => 'projects' }),
        entry('application_settings', 'gitlab_main_cell_setting', { 'organization_id' => 'organizations' }),
        entry('dropped_things', 'gitlab_main_org', { 'project_id' => 'projects' })
      ]
    end

    def entry(table_name, gitlab_schema, sharding_key)
      instance_double(Gitlab::Database::Dictionary::Entry,
        table_name: table_name, gitlab_schema: gitlab_schema, sharding_key: sharding_key)
    end

    before do
      allow(Gitlab::Database::Dictionary).to receive(:entries).and_return(entries)
    end

    it 'keeps only migrated, existing, non-excluded tables with a supported sharding key' do
      expect(table_names).to contain_exactly('projects', 'project_repositories', 'project_uploads')
    end

    it 'names sources only for tables it carries', :aggregate_failures do
      expect(manifest[:object_storage][:sources].map { |source| source[:database][:table] })
        .to eq(['project_uploads'])
      expect(manifest[:gitaly][:sources].map { |source| source[:database][:table] })
        .to eq(['project_repositories'])
    end

    context 'when no carried table has an object storage or Gitaly source' do
      let(:entries) { [entry('projects', 'gitlab_main_org', { 'organization_id' => 'organizations' })] }

      it 'leaves out both sections' do
        expect(manifest.keys).to contain_exactly(:service, :siphon, :generated_at)
      end
    end

    context 'when a connection has no database of its own' do
      let(:entries) { [entry('p_ci_builds', 'gitlab_ci', { 'project_id' => 'projects' })] }

      before do
        allow(Gitlab::Database).to receive(:has_database?).and_wrap_original do |original, name|
          name.to_s == 'ci' ? false : original.call(name)
        end
      end

      it 'files its tables under the fallback database' do
        expect(databases.keys).to eq(['gitlab_main'])
      end
    end

    context 'when CI has its own database' do
      let(:entries) do
        [
          entry('projects', 'gitlab_main_org', { 'organization_id' => 'organizations' }),
          entry('p_ci_builds', 'gitlab_ci', { 'project_id' => 'projects' })
        ]
      end

      before do
        allow(Gitlab::Database).to receive(:has_database?).and_wrap_original do |original, name|
          name.to_s == 'ci' ? true : original.call(name)
        end
      end

      it 'files each table under the database that holds it' do
        expect(databases.transform_values { |database| database[:tables].pluck(:table) })
          .to eq('gitlab_ci' => ['p_ci_builds'], 'gitlab_main' => ['projects'])
      end
    end

    context 'when another schema has a table of the same name' do
      let(:entries) { [entry('projects', 'gitlab_main_org', { 'organization_id' => 'organizations' })] }

      before do
        ApplicationRecord.connection.execute(<<~SQL)
          CREATE SCHEMA org_mover_manifest_spec;
          CREATE TABLE org_mover_manifest_spec.projects (decoy_column integer);
        SQL
      end

      it 'reads only the columns of the table on the search path' do
        columns = databases.values.flat_map { |database| database[:tables] }.first[:columns]

        expect(columns.pluck(:name)).to include('id').and exclude('decoy_column')
      end
    end
  end
end
