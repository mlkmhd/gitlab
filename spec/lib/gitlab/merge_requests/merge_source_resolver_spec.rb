# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Gitlab::MergeRequests::MergeSourceResolver, feature_category: :code_review_workflow do
  let_it_be(:project) { create(:project) }
  let_it_be(:branch_name) { 'feature' }
  let_it_be(:sha) { '0123456789abcdef0123456789abcdef01234567' }
  let_it_be(:newrev) { 'fedcba9876543210fedcba9876543210fedcba98' }

  let(:resolver) { described_class.new(project: project, branch_name: branch_name, newrev: newrev) }

  subject(:merge_source) { resolver.resolve(sha) }

  def create_merge_request(*traits, target_branch: branch_name, **attrs)
    create(:merge_request, *traits, :unique_branches, source_project: project, target_project: project,
      target_branch: target_branch, **attrs)
  end

  it 'reads from a replica that has caught up with the project, once' do
    expect(::ApplicationRecord.sticking).to receive(:find_caught_up_replica)
      .with(:project, project.id, use_primary_on_empty_location: true).once

    resolver.resolve(sha)
    resolver.resolve(newrev)
  end

  it 'returns a locked merge request that is merging the commit' do
    merge_request = create_merge_request(:locked, in_progress_merge_commit_sha: sha)

    expect(merge_source).to eq(merge_request)
  end

  it 'prefers a merged merge request with a merged state event over one without' do
    without_event = create_merge_request(:merged, merged_commit_sha: sha)
    with_event = create_merge_request(:merged, merged_commit_sha: sha)
    create(:resource_state_event, merge_request: with_event, state: :merged)

    expect(without_event.id).to be < with_event.id
    expect(merge_source).to eq(with_event)
  end

  it 'returns a merged merge request with no merged state event yet' do
    merge_request = create_merge_request(:merged, merged_commit_sha: sha)

    expect(merge_source).to eq(merge_request)
  end

  context 'when several merged merge requests have no merged state event' do
    let(:commit) { instance_double(Gitlab::Git::Commit, parent_ids: ['1111111111111111111111111111111111111111']) }

    let!(:sibling) { create_merge_request(:merged, merged_commit_sha: sha) }
    let!(:merging) { create_merge_request(:merged, merged_commit_sha: sha) }

    before do
      allow(project).to receive(:commit).with(sha).and_return(commit)
    end

    it 'returns the one whose head is a parent of the commit' do
      merging.merge_request_diff.update_column(:head_commit_sha, commit.parent_ids.first)

      expect(merge_source).to eq(merging)
    end

    it 'returns the one whose squash commit is a parent of the commit' do
      merging.update_column(:squash_commit_sha, commit.parent_ids.first)

      expect(merge_source).to eq(merging)
    end

    it 'returns the oldest when none is' do
      expect(merge_source).to eq(sibling)
    end

    it 'returns the oldest when the commit is missing' do
      allow(project).to receive(:commit).with(sha).and_return(nil)

      expect(merge_source).to eq(sibling)
    end
  end

  it 'skips a merge request that a push already marked merged' do
    merge_request = create_merge_request(:merged, merged_commit_sha: sha)
    create(:resource_state_event, merge_request: merge_request, state: :merged, source_commit: sha)

    expect(merge_source).to be_nil
  end

  it 'ignores merge requests targeting another branch' do
    create_merge_request(:locked, target_branch: 'other', in_progress_merge_commit_sha: sha)

    expect(merge_source).to be_nil
  end

  it 'falls back to the merge request that merged the pushed commit' do
    merge_request = create_merge_request(:locked, in_progress_merge_commit_sha: newrev)

    expect(merge_source).to eq(merge_request)
  end

  it 'looks up the pushed commit when the merge commit is unknown' do
    merge_request = create_merge_request(:locked, in_progress_merge_commit_sha: newrev)

    expect(resolver.resolve(nil)).to eq(merge_request)
  end
end
