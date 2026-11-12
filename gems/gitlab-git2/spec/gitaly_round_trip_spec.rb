# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'Gitaly round trip', :gitaly do
  let(:metadata) { GitalyServer.metadata }

  it 'reports the server version and the storage' do
    info = GitalyServer.stub(:Server).server_info(Gitaly::ServerInfoRequest.new, **metadata)

    expect(info.server_version).not_to be_empty
    expect(info.storage_statuses.map(&:storage_name)).to include(GitalyServer::STORAGE)
  end

  it 'rejects a request without the token' do
    expect { GitalyServer.stub(:Server).server_info(Gitaly::ServerInfoRequest.new) }
      .to raise_error(GRPC::Unauthenticated)
  end

  context 'with a repository created from a bundle' do
    let!(:repository) { FixtureRepository.create }

    after do
      FixtureRepository.remove(repository)
    end

    it 'finds the default branch' do
      response = GitalyServer.stub(:Ref)
        .find_default_branch_name(Gitaly::FindDefaultBranchNameRequest.new(repository: repository), **metadata)

      expect(response.name).to eq('refs/heads/master')
    end

    it 'finds the refs of the fixture' do
      exists = ->(ref) do
        GitalyServer.stub(:Ref)
          .ref_exists(Gitaly::RefExistsRequest.new(repository: repository, ref: ref), **metadata).value
      end

      expect(exists.call('refs/heads/feature')).to be(true)
      expect(exists.call('refs/heads/does-not-exist')).to be(false)
    end

    it 'reads a commit' do
      response = GitalyServer.stub(:Commit)
        .find_commit(Gitaly::FindCommitRequest.new(repository: repository, revision: 'master'), **metadata)

      expect(response.commit.id).to match(/\A\h{40}\z/)
    end
  end
end
