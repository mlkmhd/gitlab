# frozen_string_literal: true

require 'spec_helper'

RSpec.describe RapidDiffs::DiffSourceVersionEntity, feature_category: :code_review_workflow do
  include Gitlab::Routing.url_helpers
  include MergeRequestsHelper

  # rubocop:disable RSpec/FactoryBot/AvoidCreate -- Needs persisted objects
  let_it_be(:project) { create(:project, :repository) }

  let_it_be(:merge_request) do
    create(
      :merge_request,
      :skip_diff_creation,
      source_project: project,
      target_project: project
    )
  end

  let_it_be(:diff_1) { create(:merge_request_diff, merge_request: merge_request) }
  let_it_be(:diff_2) { create(:merge_request_diff, merge_request: merge_request) }
  # rubocop:enable RSpec/FactoryBot/AvoidCreate

  let(:current_merge_request_diff) { nil }
  let(:start_sha) { nil }
  let(:start_version_id) { nil }

  let(:options) do
    {
      merge_request: merge_request,
      version_indexes: { diff_2.id => 2, diff_1.id => 1 },
      current_merge_request_diff: current_merge_request_diff,
      start_sha: start_sha,
      start_version_id: start_version_id
    }
  end

  let(:merge_request_diff) { diff_2 }
  let(:entity) { described_class.new(merge_request_diff, options) }

  subject(:serialized) { entity.as_json }

  describe 'serialization' do
    it 'inherits attributes from DiffVersionEntity' do
      expect(serialized).to include(
        :id,
        :version_index,
        :is_merge_head,
        :latest,
        :short_commit_sha,
        :commits_count,
        :created_at
      )
    end

    it 'exposes head_sha from head_commit_sha' do
      expect(serialized[:head_sha]).to eq(merge_request_diff.head_commit_sha)
    end

    it 'exposes base_sha from base_commit_sha' do
      expect(serialized[:base_sha]).to eq(merge_request_diff.base_commit_sha)
    end

    it 'exposes start_sha from start_commit_sha' do
      expect(serialized[:start_sha]).to eq(merge_request_diff.start_commit_sha)
    end
  end

  describe 'selected' do
    context 'when only_context_commits option is true' do
      let(:options) { super().merge(only_context_commits: true) }

      before do
        allow(merge_request_diff).to receive_messages(latest?: true, merge_head?: false)
      end

      it 'returns false even for the latest version' do
        expect(serialized[:selected]).to be(false)
      end
    end

    context 'when diff is latest' do
      before do
        allow(merge_request_diff).to receive_messages(
          latest?: true,
          merge_head?: false
        )
      end

      it 'returns true' do
        expect(serialized[:selected]).to be(true)
      end
    end

    context 'when diff is merge_head' do
      before do
        allow(merge_request_diff).to receive_messages(
          latest?: false,
          merge_head?: true
        )
      end

      it 'returns true' do
        expect(serialized[:selected]).to be(true)
      end
    end

    context 'when diff is neither latest nor merge_head' do
      before do
        allow(merge_request_diff).to receive_messages(
          latest?: false,
          merge_head?: false
        )
      end

      it 'returns false' do
        expect(serialized[:selected]).to be(false)
      end
    end

    context 'when the current version is this merge request diff' do
      let(:current_merge_request_diff) { merge_request_diff }

      it 'returns true' do
        expect(serialized[:selected]).to be(true)
      end
    end

    context 'when the current version is the merge head diff' do
      let(:current_merge_request_diff) { build_stubbed(:merge_request_diff, merge_request: merge_request) }

      before do
        allow(current_merge_request_diff).to receive(:merge_head?).and_return(true)
      end

      context 'when diff is latest' do
        before do
          allow(merge_request_diff).to receive_messages(latest?: true, merge_head?: false)
        end

        it 'returns true' do
          expect(serialized[:selected]).to be(true)
        end
      end

      context 'when diff is merge_head' do
        before do
          allow(merge_request_diff).to receive_messages(latest?: false, merge_head?: true)
        end

        it 'returns true' do
          expect(serialized[:selected]).to be(true)
        end
      end

      context 'when diff is neither latest nor merge_head' do
        before do
          allow(merge_request_diff).to receive_messages(latest?: false, merge_head?: false)
        end

        it 'returns false' do
          expect(serialized[:selected]).to be(false)
        end
      end
    end
  end

  describe 'href' do
    context 'when the start version is older than this one' do
      let(:start_sha) { diff_1.head_commit_sha }
      let(:start_version_id) { diff_1.id }

      it 'returns merge_request_version_path with start_sha' do
        expected_path = merge_request_version_path(
          project,
          merge_request,
          merge_request_diff,
          start_sha: start_sha
        )

        expect(serialized[:href]).to eq(expected_path)
      end
    end

    context 'when the start version is not older than this one' do
      let(:merge_request_diff) { diff_1 }
      let(:start_sha) { diff_2.head_commit_sha }
      let(:start_version_id) { diff_2.id }

      it 'returns merge_request_version_path without start_sha' do
        expected_path = merge_request_version_path(
          project,
          merge_request,
          merge_request_diff
        )

        expect(serialized[:href]).to eq(expected_path)
      end
    end

    context 'when this is the start version' do
      let(:merge_request_diff) { diff_1 }
      let(:start_sha) { diff_1.head_commit_sha }
      let(:start_version_id) { diff_1.id }

      it 'returns merge_request_version_path without start_sha' do
        expected_path = merge_request_version_path(
          project,
          merge_request,
          merge_request_diff
        )

        expect(serialized[:href]).to eq(expected_path)
      end
    end

    context 'when start_sha is not present' do
      it 'returns merge_request_version_path without start_sha' do
        expected_path = merge_request_version_path(
          project,
          merge_request,
          merge_request_diff
        )

        expect(serialized[:href]).to eq(expected_path)
      end
    end
  end
end
