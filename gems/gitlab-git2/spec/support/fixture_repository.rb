# frozen_string_literal: true

require 'open3'

# Creates repositories in `GitalyServer` from the monolith's
# `spec/support/gitlab-git-test.git` fixture, through Gitaly's
# `CreateRepositoryFromBundle`, as `create(:project, :repository)` does.
module FixtureRepository
  SOURCE = File.expand_path('../../../../spec/support/gitlab-git-test.git', __dir__)
  CHUNK_SIZE = 128 * 1024

  class << self
    def bundle
      @bundle ||= begin
        path = File.join(Dir.mktmpdir('gitlab-git-fixture'), 'gitlab-git-test.bundle')
        _, status = Open3.capture2e('git', '-C', SOURCE, 'bundle', 'create', path, '--all')
        raise "Could not bundle #{SOURCE}" unless status.success?

        path
      end
    end

    def create
      repository = Gitaly::Repository.new(storage_name: GitalyServer::STORAGE,
        relative_path: "@gitlab-git-spec/#{SecureRandom.hex(8)}.git")

      GitalyServer.stub(:Repository).create_repository_from_bundle(requests(repository), **GitalyServer.metadata)

      repository
    end

    def remove(repository)
      GitalyServer.stub(:Repository)
        .remove_repository(Gitaly::RemoveRepositoryRequest.new(repository: repository), **GitalyServer.metadata)
    end

    private

    def requests(repository)
      Enumerator.new do |y|
        File.open(bundle, 'rb') do |file|
          first = true

          until file.eof?
            y << Gitaly::CreateRepositoryFromBundleRequest.new(repository: (repository if first),
              data: file.read(CHUNK_SIZE))
            first = false
          end
        end
      end
    end
  end
end
