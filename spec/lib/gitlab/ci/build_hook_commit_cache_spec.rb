# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Gitlab::Ci::BuildHookCommitCache, :clean_gitlab_redis_repository_cache,
  feature_category: :pipeline_composition do
  let_it_be_with_reload(:project) { create(:project) }
  let_it_be_with_refind(:project_repository) do
    create(:project_repository, project: project, disk_path: project.repository.disk_path)
  end

  let(:sha) { 'a' * 40 }
  let(:metadata) do
    { id: sha, message: "A commit\n", author_name: 'Commit author', author_email: 'author@example.com' }
  end

  let(:commit) { Commit.from_hash(metadata, project) }
  let(:cache_store) { Gitlab::Redis::RepositoryCache.cache_store }
  let(:loader) { instance_double(Proc) }

  subject(:cache) { described_class.new(project, sha) }

  def fetch
    cache.fetch { loader.call }
  end

  before do
    allow(loader).to receive(:call) { commit }
  end

  describe '#fetch' do
    it 'loads the commit once across cache instances' do
      expect(loader).to receive(:call).once.and_return(commit)

      expect(fetch).to eq(commit)
      cached_commit = described_class.new(project, sha).fetch { loader.call }

      expect(cached_commit).to be_a(Commit)
      expect(cached_commit).not_to equal(commit)
      expect(cached_commit.container).to eq(project)
      expect(cached_commit.message).to eq(metadata[:message])
      expect(cached_commit.author_name).to eq(metadata[:author_name])
      expect(cached_commit.author_email).to eq(metadata[:author_email])
    end

    it 'stores only the immutable commit metadata with a finite expiry' do
      allow(cache_store).to receive(:write).and_call_original
      expect(cache_store).to receive(:write)
        .with(anything, metadata, expires_in: 10.minutes).and_call_original

      fetch
    end

    it 'expires cached metadata' do
      expect(loader).to receive(:call).twice.and_return(commit)

      fetch
      travel_to(11.minutes.from_now) { fetch }
    end

    it 'does not share metadata across SHAs' do
      fetch
      other_sha = 'b' * 40
      other_commit = Commit.from_hash(metadata.merge(id: other_sha, message: 'Other commit'), project)

      result = described_class.new(project, other_sha).fetch { other_commit }

      expect(result.id).to eq(other_sha)
      expect(result.message).to eq('Other commit')
    end

    it 'does not share metadata across projects' do
      fetch
      other_project = create(:project)
      create(:project_repository, project: other_project, disk_path: other_project.repository.disk_path)
      other_commit = Commit.from_hash(metadata.merge(message: 'Another repository'), other_project)

      result = described_class.new(other_project, sha).fetch { other_commit }

      expect(result.container).to eq(other_project)
      expect(result.message).to eq('Another repository')
    end

    it 'accepts a full SHA256 object ID' do
      sha256 = 'b' * 64
      commit = Commit.from_hash(metadata.merge(id: sha256), project)
      cache = described_class.new(project, sha256)

      expect(loader).to receive(:call).once.and_return(commit)

      2.times { expect(cache.fetch { loader.call }.id).to eq(sha256) }
    end

    it 'preserves binary strings across a cache round trip' do
      metadata[:message] = "A commit\x00\xFF\n".b
      expect(loader).to receive(:call).once.and_return(commit)

      fetch
      result = fetch

      expect(result.message).to eq(metadata[:message])
      expect(result.message.encoding).to eq(Encoding::ASCII_8BIT)
    end

    context 'when the repository is read only' do
      before do
        allow(project).to receive(:repository_read_only?).and_return(true)
      end

      it 'bypasses both cache reads and writes' do
        expect(cache_store).not_to receive(:read)
        expect(cache_store).not_to receive(:write)
        expect(loader).to receive(:call).twice.and_return(commit)

        2.times { expect(fetch).to eq(commit) }
      end
    end

    context 'when the project is pending deletion' do
      before do
        allow(project).to receive(:pending_delete?).and_return(true)
      end

      it 'bypasses both cache reads and writes' do
        expect(cache_store).not_to receive(:read)
        expect(cache_store).not_to receive(:write)

        expect(fetch).to eq(commit)
      end
    end

    context 'when the nullable project flags are NULL' do
      it 'still caches' do
        Project.where(id: project.id).update_all(repository_read_only: nil, pending_delete: nil)
        project.reload
        expect(loader).to receive(:call).once.and_return(commit)

        expect(fetch).to eq(commit)
        expect(described_class.new(project, sha).fetch { loader.call }).to eq(commit)
      end
    end

    context 'when a commit is missing' do
      before do
        allow(loader).to receive(:call).and_return(nil)
      end

      it 'does not cache the missing result' do
        expect(loader).to receive(:call).twice.and_return(nil)

        2.times { expect(fetch).to be_nil }
      end
    end

    context 'when metadata exceeds the cache size limit' do
      before do
        metadata[:message] = 'a' * 65.kilobytes
      end

      it 'returns the commit without caching its metadata' do
        expect(loader).to receive(:call).twice.and_return(commit)

        2.times { expect(fetch.message).to eq(metadata[:message]) }
      end
    end

    context 'when the returned commit ID does not match the requested SHA' do
      before do
        metadata[:id] = 'b' * 40
      end

      it 'does not cache the mismatched commit' do
        expect(loader).to receive(:call).twice.and_return(commit)

        2.times { expect(fetch).to eq(commit) }
      end
    end

    context 'when the revision is not a full object ID' do
      let(:sha) { 'main' }

      it 'bypasses cache access' do
        expect(cache_store).not_to receive(:read)
        expect(cache_store).not_to receive(:write)

        expect(fetch).to eq(commit)
      end
    end

    context 'when Redis reads fail' do
      before do
        allow(cache_store).to receive(:read).and_raise(Redis::BaseConnectionError)
      end

      it 'loads the original commit once' do
        expect(loader).to receive(:call).once.and_return(commit)

        expect(fetch).to eq(commit)
      end
    end

    context 'when Redis metadata writes fail' do
      before do
        allow(cache_store).to receive(:write).and_call_original
        allow(cache_store).to receive(:write).with(anything, metadata, expires_in: anything)
          .and_raise(Redis::BaseConnectionError)
      end

      it 'returns the loaded commit without loading it again' do
        expect(loader).to receive(:call).once.and_return(commit)

        expect(fetch).to eq(commit)
      end
    end
  end

  describe 'cache read metrics', :prometheus, :aggregate_failures do
    def read_count(result)
      metric = Gitlab::Metrics.client.get(:gitlab_ci_build_hook_commit_cache_reads_total)

      metric&.get(result: result).to_f
    end

    it 'counts a cold read as a miss and a warm read as a hit' do
      expect(loader).to receive(:call).once.and_return(commit)

      expect { 2.times { fetch } }
        .to change { read_count('miss') }.by(1)
        .and change { read_count('hit') }.by(1)
    end

    it 'counts malformed metadata as a miss' do
      allow(cache_store).to receive(:read).and_return(metadata.except(:author_email))

      expect { fetch }
        .to change { read_count('miss') }.by(1)
        .and not_change { read_count('hit') }
    end

    it 'does not count a bypass for a revision that is not a full object ID' do
      cache = described_class.new(project, 'main')

      expect { cache.fetch { loader.call } }.not_to change { [read_count('hit'), read_count('miss')] }
    end

    it 'counts a Redis read fallback as a miss' do
      allow(cache_store).to receive(:read).and_raise(Redis::BaseConnectionError)
      expect(loader).to receive(:call).once.and_return(commit)

      expect { fetch }
        .to change { read_count('miss') }.by(1)
        .and not_change { read_count('hit') }
    end
  end

  describe 'metadata validation' do
    it 'rejects malformed cached entries and returns the original commit', :aggregate_failures do
      cached_key = nil
      allow(cache_store).to receive(:write).and_wrap_original do |original, key, value, **options|
        cached_key = key if value.is_a?(Hash)
        original.call(key, value, **options)
      end
      fetch
      expect(cached_key).to be_present

      malformed_entries = [
        metadata.except(:author_email).merge(unexpected: 'same number of keys'),
        metadata.merge(author_name: ['not a string']),
        'not a hash'
      ]
      expect(loader).to receive(:call).exactly(malformed_entries.size).times.and_return(commit)

      malformed_entries.each do |malformed|
        cache_store.write(cached_key, malformed, expires_in: described_class::TTL)
        expect(fetch).to equal(commit)
      end
    end

    it 'caches exactly the byte limit but skips a value one byte larger', :aggregate_failures do
      fixed_bytes = metadata.except(:message).values.sum(&:bytesize)
      at_limit = metadata.merge(message: 'x' * (described_class::MAX_BYTES - fixed_bytes))
      over_limit = at_limit.merge(id: 'b' * 40, message: "#{at_limit[:message]}x")
      at_limit_commit = Commit.from_hash(at_limit, project)
      over_limit_commit = Commit.from_hash(over_limit, project)
      at_limit_cache = described_class.new(project, at_limit[:id])
      over_limit_cache = described_class.new(project, over_limit[:id])

      expect(loader).to receive(:call).exactly(3).times
        .and_return(at_limit_commit, over_limit_commit, over_limit_commit)

      2.times do
        expect(at_limit_cache.fetch { loader.call }.message).to eq(at_limit[:message])
      end
      2.times do
        expect(over_limit_cache.fetch { loader.call }.message).to eq(over_limit[:message])
      end
    end
  end

  describe 'fault handling' do
    it 'loads the origin on every nil read and tolerates false writes', :aggregate_failures do
      allow(cache_store).to receive_messages(read: nil, write: false)
      expect(loader).to receive(:call).twice.and_return(commit)

      2.times { expect(fetch).to equal(commit) }
    end

    it 'tolerates RedisClient errors from both reads and writes' do
      allow(cache_store).to receive(:read).and_raise(RedisClient::Error, 'read unavailable')
      allow(cache_store).to receive(:write).and_raise(RedisClient::Error, 'write unavailable')
      expect(loader).to receive(:call).once.and_return(commit)

      expect(fetch).to equal(commit)
    end

    it 'propagates the origin error without storing metadata' do
      expect(loader).to receive(:call).once.and_raise(Gitlab::Git::Repository::NoRepository, 'origin unavailable')
      expect(cache_store).not_to receive(:write)

      expect { fetch }.to raise_error(Gitlab::Git::Repository::NoRepository, 'origin unavailable')
    end

    it 'bypasses the cache on a globally read-only database', :aggregate_failures do
      allow(Gitlab::Database).to receive(:read_only?).and_return(true)
      expect(cache_store).not_to receive(:read)
      expect(cache_store).not_to receive(:write)
      expect(loader).to receive(:call).once.and_return(commit)

      expect(fetch).to equal(commit)
    end
  end
end
