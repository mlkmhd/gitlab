# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Import::Offline::Exports::SnippetRepositoriesExportService, feature_category: :importers do
  let_it_be(:project) { create(:project) }
  let_it_be(:snippet_with_repository) { create(:project_snippet, :repository, project: project) }
  let_it_be(:snippet_without_repository) { create(:project_snippet, project: project) }

  let(:export_path) { Dir.mktmpdir }

  subject(:service) { described_class.new(project, export_path) }

  after do
    FileUtils.rm_rf(export_path)
  end

  def bundle_filename_for(snippet)
    Import::Offline::SnippetRepositoryBundle.filename_for(snippet)
  end

  describe '#execute' do
    it 'bundles each snippet repository to disk under its bundle filename' do
      service.execute

      bundle_path = File.join(export_path, bundle_filename_for(snippet_with_repository))
      missing_bundle_path = File.join(export_path, bundle_filename_for(snippet_without_repository))

      expect(File.exist?(bundle_path)).to be(true)
      expect(File.exist?(missing_bundle_path)).to be(false)
      expect(Dir.children(export_path)).to contain_exactly(File.basename(bundle_path))
      expect(service.exported_objects_count).to eq(2)
    end

    context 'when snippets share a title and creation millisecond' do
      let_it_be(:project) { create(:project) }
      let_it_be(:created_at) { Time.zone.parse('2020-01-02T03:04:05Z') }
      let_it_be(:duplicates) do
        create_list(:project_snippet, 2, :repository, project: project, title: 'dup', created_at: created_at)
      end

      let_it_be(:unique_snippet) { create(:project_snippet, :repository, project: project) }

      it 'skips the ambiguous snippets and logs a warning', :aggregate_failures do
        duplicates.each do |snippet|
          expect(Gitlab::Export::Logger).to receive(:warn).with(
            hash_including(
              Labkit::Fields::GL_PROJECT_ID => project.id,
              snippet_id: snippet.id,
              message: /same title and creation time/
            )
          )
        end

        service.execute

        expect(Dir.children(export_path)).to contain_exactly(bundle_filename_for(unique_snippet))
        expect(service.exported_objects_count).to eq(3)
      end
    end

    context 'when the project has more snippets' do
      let_it_be(:project) { create(:project) }
      let_it_be(:snippet) { create(:project_snippet, :repository, project: project) }

      def execute_service
        Dir.mktmpdir { |dir| described_class.new(project, dir).execute }
      end

      it 'does not run additional queries per snippet' do
        control = ActiveRecord::QueryRecorder.new(skip_cached: false) { execute_service }

        create_list(:project_snippet, 2, :repository, project: project)
        create(:project_snippet, project: project)

        expect { execute_service }.not_to exceed_all_query_limit(control)
      end
    end

    context 'when bundling a snippet repository raises' do
      let_it_be(:project) { create(:project) }
      let_it_be(:failing_snippet) { create(:project_snippet, :repository, project: project) }
      let_it_be(:other_snippet) { create(:project_snippet, :repository, project: project) }

      let(:error) { StandardError.new('Gitaly timeout') }

      before do
        failing_filename = bundle_filename_for(failing_snippet)
        failing_bundle_service = instance_double(::BulkImports::RepositoryBundleExportService)

        allow(failing_bundle_service).to receive(:execute) do
          File.write(File.join(export_path, failing_filename), 'partial')
          raise error
        end

        allow(::BulkImports::RepositoryBundleExportService).to receive(:new).and_call_original
        allow(::BulkImports::RepositoryBundleExportService).to receive(:new)
          .with(anything, export_path, File.basename(failing_filename, '.bundle'))
          .and_return(failing_bundle_service)
      end

      it 'skips the snippet, removes its partial bundle, and exports the rest', :aggregate_failures do
        expect(Gitlab::ErrorTracking).to receive(:log_exception).with(
          error,
          hash_including(
            Labkit::Fields::GL_PROJECT_ID => project.id,
            snippet_id: failing_snippet.id
          )
        )

        service.execute

        expect(Dir.children(export_path)).to contain_exactly(bundle_filename_for(other_snippet))
        expect(service.exported_objects_count).to eq(2)
      end
    end
  end
end
