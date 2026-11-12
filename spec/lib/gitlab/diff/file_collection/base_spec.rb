# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Gitlab::Diff::FileCollection::Base, feature_category: :code_review_workflow do
  let(:merge_request) { create(:merge_request) }
  let(:diffable) { merge_request.merge_request_diff }
  let(:diff_options) { {} }

  describe '#overflow?' do
    subject(:overflown) { described_class.new(diffable, project: merge_request.project, diff_options: diff_options).overflow? }

    context 'when it is not overflown' do
      it 'returns false' do
        expect(overflown).to be(false)
      end
    end

    context 'when it is overflown' do
      let(:diff_options) { { max_files: 1 } }

      it 'returns true' do
        expect(overflown).to be(true)
      end
    end
  end

  describe '#raw_diff_files' do
    let(:max_blob_size) { 10 }

    it 'returns diffs that contain a maximum of max_blob_size of data' do
      allow(described_class).to receive(:max_blob_size).and_return(max_blob_size)

      expect(described_class.new(diffable, project: merge_request.project).raw_diff_files.all? { |file| file.max_blob_size == max_blob_size }).to be_truthy
    end

    context 'when the diffs contain notebooks', :use_clean_rails_redis_caching, :request_store do
      let_it_be(:project) { create(:project, :repository) }
      # Changes, adds and deletes a notebook.
      let(:commit) { project.commit('5d6ed1503801ca9dc28e95eeb85a7cf863527aee') }
      let(:diff_options) { { use_extra_viewer_as_main: true } }
      let(:keys) do
        commit.raw_diffs.map do |diff|
          [
            'notebook_diff', Gitlab::Diff::Rendered::Notebook::DiffCache::VERSION, project.id, diff.from_id, diff.to_id
          ].join(':')
        end
      end

      def collection(**options)
        described_class.new(
          commit, project: project, diff_options: diff_options.merge(options), diff_refs: commit.diff_refs
        )
      end

      def rendered_output(diff_files)
        diff_files.map { |file| [file.class, file.diff.diff, file.highlighted_diff_lines.map(&:to_hash)] }
      end

      before do
        allow(IpynbDiff).to receive(:diff).and_call_original
      end

      it 'reads the render cache entries of all notebooks in one call' do
        expect(Rails.cache).to receive(:read_multi).with(*keys).once.and_call_original
        expect(Rails.cache).not_to receive(:read)

        diff_files = collection.raw_diff_files

        expect(diff_files).to all(be_a(Gitlab::Diff::Rendered::Notebook::DiffFile))
        expect(IpynbDiff).to have_received(:diff).exactly(keys.size).times
      end

      it 'renders the same files as single cache reads' do
        expect(Rails.cache).to receive(:read).exactly(keys.size).times.and_call_original

        single_reads = rendered_output(collection(use_extra_viewer_as_main: false).raw_diff_files.map(&:rendered))
        batched = rendered_output(collection.raw_diff_files)

        expect(batched).to eq(single_reads)
        expect(IpynbDiff).to have_received(:diff).exactly(keys.size).times
      end

      it 'renders the same files as without the cache when every entry misses' do
        batched = rendered_output(collection.raw_diff_files)

        allow_next_instance_of(Gitlab::Diff::Rendered::Notebook::DiffCache) do |cache|
          allow(cache).to receive(:fetch).and_yield
        end
        uncached = rendered_output(collection.raw_diff_files)

        expect(batched).to eq(uncached)
        expect(IpynbDiff).to have_received(:diff).exactly(keys.size * 2).times
      end

      context 'when the diffs also contain a text file' do
        let_it_be(:sha) do
          notebook = Gitlab::Json.generate(
            cells: [{ cell_type: 'code', execution_count: 1, metadata: {}, outputs: [], source: ['1 + 1'] }],
            metadata: {}, nbformat: 4, nbformat_minor: 5
          )

          project.repository.commit_files(
            project.first_owner, branch_name: 'notebook-and-text', start_branch_name: 'master', message: 'Add files',
            actions: [
              { action: :create, file_path: 'notebook.ipynb', content: notebook },
              { action: :create, file_path: 'notes.txt', content: "plain text\n" }
            ]
          )
        end

        # Commit memoizes its diff stats, so a frozen let_it_be commit cannot be reused.
        let(:commit) { project.commit(sha) }

        it 'prefetches only the notebook key, and swaps only the notebook for its rendered file' do
          notebook_diff = commit.raw_diffs.find { |diff| diff.new_path == 'notebook.ipynb' }
          notebook_key = ['notebook_diff', Gitlab::Diff::Rendered::Notebook::DiffCache::VERSION, project.id, nil,
            notebook_diff.to_id].join(':')
          expect(Rails.cache).to receive(:read_multi).with(notebook_key).once.and_call_original

          diff_files = collection.raw_diff_files.index_by(&:file_path)

          expect(diff_files['notebook.ipynb']).to be_a(Gitlab::Diff::Rendered::Notebook::DiffFile)
          expect(diff_files['notes.txt']).to be_an_instance_of(Gitlab::Diff::File)
          expect(diff_files.values.map(&:rendered?)).to contain_exactly(true, false)
        end

        context 'when use_extra_viewer_as_main is off' do
          let(:diff_options) { { use_extra_viewer_as_main: false } }

          it 'does not prefetch or render' do
            expect(Gitlab::Diff::Rendered::Notebook::DiffCache).not_to receive(:prefetch)

            expect(collection.raw_diff_files).to all(be_an_instance_of(Gitlab::Diff::File))
            expect(IpynbDiff).not_to have_received(:diff)
          end
        end
      end
    end
  end

  describe '#diff_paths' do
    subject(:diff_paths) { described_class.new(diffable, project: merge_request.project).diff_paths }

    let(:diffable) { instance_double(MergeRequestDiff, raw_diffs: Gitlab::Git::DiffCollection.new(raw_diffs)) }
    let(:raw_diffs) do
      [
        { old_path: 'old.ipynb', new_path: 'new.ipynb', renamed_file: true, diff: '' },
        { old_path: 'added.rb', new_path: 'added.rb', new_file: true, diff: "@@ -0,0 +1 @@\n+a\n" },
        { old_path: 'deleted.rb', new_path: 'deleted.rb', deleted_file: true, diff: "@@ -1 +0,0 @@\n-a\n" }
      ]
    end

    let(:expected_paths) { %w[old.ipynb new.ipynb added.rb deleted.rb] }

    it 'returns the old and new paths without decorating the diff files' do
      expect(Gitlab::Diff::File).not_to receive(:new)

      expect(diff_paths).to eq(expected_paths)
    end
  end

  describe 'rename diff stats' do
    let(:project) { merge_request.project }
    let(:diff_refs) do
      instance_double(Gitlab::Diff::DiffRefs, base_sha: 'base', head_sha: 'head')
    end

    # Gitaly reports inflated stats because it treats the rename as a full rewrite:
    # 57 additions (entire new file) and 13 deletions (entire old file).
    # These should be ignored in favour of parsing the actual diff lines.
    let(:new_path_stats) { Gitaly::DiffStats.new(path: 'new.py', additions: 57, deletions: 0) }
    let(:old_path_stats) { Gitaly::DiffStats.new(path: 'old.py', additions: 0, deletions: 13) }
    let(:diff_stats_collection) { Gitlab::Git::DiffStatsCollection.new([new_path_stats, old_path_stats]) }
    let(:renamed_diff) do
      {
        old_path: 'old.py',
        new_path: 'new.py',
        renamed_file: true,
        new_file: false,
        deleted_file: false,
        diff: <<~DIFF
          @@ -1,4 +1,5 @@
          def hello
          -    print("world")
          +    print("world!")
          +    print("done")
          end
        DIFF
      }
    end

    let(:diff_collection) { Gitlab::Git::DiffCollection.new([renamed_diff]) }
    let(:diffable) do
      instance_double(
        MergeRequestDiff,
        raw_diffs: diff_collection,
        diff_stats: diff_stats_collection
      )
    end

    it 'ignores Gitaly stats and counts actual diff lines for renamed files' do
      diff_file = described_class.new(diffable, project: project, diff_refs: diff_refs).diff_files.first

      expect(diff_file.renamed_file?).to be(true)
      # Gitaly stats report 57 additions and 13 deletions (full-file rewrite),
      # but the actual diff has only 2 added lines and 1 removed line.
      expect(diff_file.added_lines).to eq(2)
      expect(diff_file.removed_lines).to eq(1)
    end
  end
end
