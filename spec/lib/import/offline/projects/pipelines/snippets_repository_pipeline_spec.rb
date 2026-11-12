# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Import::Offline::Projects::Pipelines::SnippetsRepositoryPipeline, feature_category: :importers do
  let_it_be(:user) { create(:user) }
  let_it_be(:group) { create(:group, owners: user) }
  # The :repository trait bundles gitlab-test, which fails snippet validation (multiple branches and tags)
  let_it_be(:source_snippet) do
    create(:project_snippet, :empty_repo, created_at: '2020-01-02T03:04:05Z').tap do |snippet|
      snippet.repository.create_file(
        snippet.author, 'file.txt', 'content', message: 'Add file', branch_name: snippet.default_branch
      )
    end
  end

  let_it_be_with_reload(:bulk_import) { create(:bulk_import, :with_offline_configuration, user: user) }

  let_it_be(:project) { create(:project, group: group) }

  let!(:snippet) do
    create(
      :project_snippet,
      project: project,
      title: source_snippet.title,
      description: source_snippet.description,
      created_at: source_snippet.created_at,
      updated_at: source_snippet.updated_at
    )
  end

  let(:entity) do
    create(
      :bulk_import_entity,
      :project_entity,
      bulk_import: bulk_import,
      project: project,
      source_full_path: 'source/full/path',
      destination_namespace: group.full_path
    )
  end

  let(:tracker) { create(:bulk_import_tracker, entity: entity) }
  let(:context) { BulkImports::Pipeline::Context.new(tracker) }
  let(:tmpdir) { Dir.mktmpdir }
  let(:bundle_filename) { Import::Offline::SnippetRepositoryBundle.filename_for(source_snippet) }
  let(:expected_bundle_path) { File.join(tmpdir, bundle_filename) }
  let(:bundle_path) { expected_bundle_path }

  subject(:pipeline) { described_class.new(context) }

  before do
    source_snippet.repository.bundle_to_disk(bundle_path)

    allow(Dir).to receive(:mktmpdir).with('bulk_imports').and_return(tmpdir)
    allow(pipeline).to receive(:set_source_objects_counter)
  end

  after do
    FileUtils.rm_rf(tmpdir)
  end

  describe 'pipeline parts' do
    it { expect(described_class).to include_module(BulkImports::Pipeline) }
    it { expect(described_class).to include_module(BulkImports::Pipeline::Runner) }
    it { expect(described_class).to include_module(BulkImports::Pipeline::IndexCacheStrategy) }

    it 'is a file extraction pipeline' do
      expect(described_class.file_extraction_pipeline?).to be(true)
    end

    it 'does not abort on failure' do
      expect(described_class.abort_on_failure?).to be_falsey
    end

    it 'uses the snippet repositories relation' do
      expect(described_class.relation).to eq('snippet_repositories')
    end
  end

  describe '#run', :clean_gitlab_redis_shared_state do
    before do
      allow(pipeline).to receive(:extract).and_return(BulkImports::Pipeline::ExtractedData.new(data: [snippet]))
    end

    it 'imports the snippet repository and removes the tmpdir' do
      expect { pipeline.run }.to change { snippet.reload.repository_exists? }.from(false).to(true)

      expect(snippet.snippet_repository).to be_present
      expect(snippet.repository.commit).to be_present
      expect(snippet.statistics.reload.commit_count).to eq(1)
      expect(Dir.exist?(tmpdir)).to be(false)
    end

    it 'skips already processed snippets on rerun' do
      pipeline.run

      expect(pipeline).not_to receive(:load)

      pipeline.run
    end

    context 'when the bundle is invalid' do
      before do
        allow_next_instance_of(Snippets::RepositoryValidationService) do |service|
          allow(service).to receive(:execute).and_return(ServiceResponse.error(message: 'invalid'))
        end
      end

      it 'records a failure and does not leave a repository or SnippetRepository behind', :aggregate_failures do
        expect(Snippets::UpdateStatisticsService).not_to receive(:new)

        pipeline.run

        expect(SnippetRepository.where(snippet_id: snippet.id).exists?).to be(false)
        expect(snippet.reload.repository_exists?).to be(false)
        expect(entity.reload.failed?).to be(false)
        expect(entity.failures.first).to have_attributes(
          exception_class: described_class::SnippetRepositoryError.name,
          exception_message: 'invalid',
          source_title: snippet.title
        )
      end
    end

    context 'when one snippet fails and the next is valid' do
      let!(:valid_snippet) { create(:project_snippet, project: project, title: 'valid') }

      before do
        # The pipeline finds bundles by title and created_at, and the top-level `before` writes one only for snippet.
        # Without this copy, valid_snippet has no bundle and is skipped as missing.
        FileUtils.cp(bundle_path, File.join(tmpdir, Import::Offline::SnippetRepositoryBundle.filename_for(valid_snippet)))

        allow(pipeline).to receive(:extract)
          .and_return(BulkImports::Pipeline::ExtractedData.new(data: [snippet, valid_snippet]))

        allow(Snippets::RepositoryValidationService).to receive(:new).and_call_original
        allow(Snippets::RepositoryValidationService).to receive(:new).with(anything, snippet).and_return(
          instance_double(Snippets::RepositoryValidationService, execute: ServiceResponse.error(message: 'invalid'))
        )
      end

      it 'records a failure for the invalid snippet and imports the valid one', :aggregate_failures do
        pipeline.run

        expect(snippet.reload.repository_exists?).to be(false)
        expect(valid_snippet.reload.repository_exists?).to be(true)
        expect(entity.failures.map(&:source_title)).to contain_exactly(snippet.title)
      end
    end

    context 'when a snippet in another project matches the bundle' do
      let_it_be(:other_project) { create(:project, group: group) }

      let!(:other_project_snippet) do
        create(
          :project_snippet,
          project: other_project,
          title: source_snippet.title,
          created_at: source_snippet.created_at
        )
      end

      before do
        allow(pipeline).to receive(:extract).and_call_original
        allow(BulkImports::FileDownloadService).to receive(:for_context)
          .and_return(instance_double(BulkImports::FileDownloadService, execute: nil))
        allow(BulkImports::FileDecompressionService).to receive(:new)
          .and_return(instance_double(BulkImports::FileDecompressionService, execute: nil))
        allow(BulkImports::ArchiveExtractionService).to receive(:new)
          .and_return(instance_double(BulkImports::ArchiveExtractionService, execute: nil))
      end

      it 'imports the bundle only into the snippet of the destination project', :aggregate_failures do
        # Fresh records: `exists?` memoizes false on the repository, and `reload` keeps it
        expect { pipeline.run }
          .to change { Snippet.find(snippet.id).repository_exists? }.from(false).to(true)
          .and not_change { Snippet.find(other_project_snippet.id).repository_exists? }.from(false)

        expect(SnippetRepository.where(snippet_id: other_project_snippet.id).exists?).to be(false)
      end
    end
  end

  describe '#extract' do
    it 'downloads and extracts the archive, then yields the project snippets' do
      download_service = instance_double(BulkImports::FileDownloadService)
      decompression_service = instance_double(BulkImports::FileDecompressionService)
      extraction_service = instance_double(BulkImports::ArchiveExtractionService)

      expect(BulkImports::FileDownloadService)
        .to receive(:for_context)
        .with(
          context: context,
          relation: 'snippet_repositories',
          tmpdir: tmpdir,
          filename: 'snippet_repositories.tar.gz')
        .and_return(download_service)
      expect(BulkImports::FileDecompressionService)
        .to receive(:new)
        .with(tmpdir: tmpdir, filename: 'snippet_repositories.tar.gz', context: context)
        .and_return(decompression_service)
      expect(BulkImports::ArchiveExtractionService)
        .to receive(:new)
        .with(tmpdir: tmpdir, filename: 'snippet_repositories.tar')
        .and_return(extraction_service)

      expect(download_service).to receive(:execute)
      expect(decompression_service).to receive(:execute)
      expect(extraction_service).to receive(:execute)

      extracted_data = pipeline.extract(context)

      expect(extracted_data.data).to be_a(Enumerator)
      expect(extracted_data.data.to_a).to contain_exactly(snippet)
    end
  end

  describe '#load' do
    it 'creates the repository from the matching bundle' do
      expect(snippet.repository).to receive(:create_from_bundle).with(expected_bundle_path).and_call_original

      pipeline.load(context, snippet)

      expect(snippet.repository_exists?).to be(true)
      expect(snippet.snippet_repository.shard_name).to eq(snippet.repository.storage)
    end

    context 'when the repository already exists' do
      before do
        snippet.repository.create_from_bundle(bundle_path)
      end

      it 'does not recreate the repository but still tracks and validates it' do
        expect(snippet.repository).not_to receive(:create_from_bundle)
        expect(Snippets::UpdateStatisticsService).to receive(:new).with(snippet).and_call_original

        pipeline.load(context, snippet)

        expect(snippet.snippet_repository).to be_present
      end
    end

    context 'when no bundle matches the snippet' do
      let(:bundle_path) { File.join(tmpdir, 'other.bundle') }

      it 'logs and skips the snippet' do
        expect(snippet.repository).not_to receive(:create_from_bundle)
        expect_next_instance_of(BulkImports::Logger) do |logger|
          expect(logger).to receive(:info).with(
            hash_including(message: 'Snippet repository bundle not found, skipping', snippet_id: snippet.id)
          )
        end

        pipeline.load(context, snippet)

        expect(snippet.repository_exists?).to be(false)
      end
    end

    context 'when another snippet in the project has the same title and creation time' do
      before do
        create(:project_snippet, project: project, title: snippet.title, created_at: snippet.created_at)
      end

      it 'raises without touching the repository', :aggregate_failures do
        expect(snippet.repository).not_to receive(:create_from_bundle)

        expect { pipeline.load(context, snippet) }
          .to raise_error(described_class::SnippetRepositoryError, /same title and creation time/)

        expect(snippet.repository_exists?).to be(false)
      end
    end

    context 'when the bundle path is a directory' do
      let(:bundle_path) { File.join(tmpdir, 'ignored.bundle') }

      it 'raises without touching the repository', :aggregate_failures do
        FileUtils.mkdir_p(expected_bundle_path)

        expect(snippet.repository).not_to receive(:create_from_bundle)

        expect { pipeline.load(context, snippet) }
          .to raise_error(described_class::SnippetRepositoryError, /not a regular file/)

        expect(snippet.repository_exists?).to be(false)
      end
    end

    context 'when the bundle path is a symlink' do
      let(:bundle_path) { File.join(tmpdir, 'target.bundle') }

      it 'raises without touching the repository', :aggregate_failures do
        FileUtils.ln_s(bundle_path, expected_bundle_path)

        expect(snippet.repository).not_to receive(:create_from_bundle)

        expect { pipeline.load(context, snippet) }
          .to raise_error(described_class::SnippetRepositoryError, /not a regular file/)

        expect(snippet.repository_exists?).to be(false)
      end
    end

    context 'when the bundle has multiple hard links' do
      it 'raises without touching the repository', :aggregate_failures do
        FileUtils.link(bundle_path, File.join(tmpdir, 'hard_link'))

        expect(snippet.repository).not_to receive(:create_from_bundle)

        expect { pipeline.load(context, snippet) }
          .to raise_error(described_class::SnippetRepositoryError, /not a regular file/)

        expect(snippet.repository_exists?).to be(false)
      end
    end

    context 'when the bundle fails validation' do
      before do
        allow_next_instance_of(Snippets::RepositoryValidationService) do |service|
          allow(service).to receive(:execute).and_return(ServiceResponse.error(message: 'invalid'))
        end
      end

      it 'removes the repository and raises with the validation message', :aggregate_failures do
        expect { pipeline.load(context, snippet) }
          .to raise_error(described_class::SnippetRepositoryError, 'invalid')

        expect(SnippetRepository.where(snippet_id: snippet.id).exists?).to be(false)
        expect(snippet.repository_exists?).to be(false)
      end
    end

    context 'when the tmpdir is outside the allowed directory' do
      let(:tmpdir) { Dir.mktmpdir(nil, Rails.root.join('tmp')) }

      it 'raises an error' do
        expect { pipeline.load(context, snippet) }.to raise_error(StandardError, /is not allowed/)
      end
    end
  end

  describe '#after_run' do
    it 'removes the tmpdir' do
      allow(FileUtils).to receive(:rm_rf).and_call_original
      expect(FileUtils).to receive(:rm_rf).with(tmpdir).and_call_original

      pipeline.after_run(nil)

      expect(Dir.exist?(tmpdir)).to be(false)
    end
  end
end
