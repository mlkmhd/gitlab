# frozen_string_literal: true

require 'fast_spec_helper'
require 'open3'
require 'tmpdir'

RSpec.describe 'set_migrations_diff_base shell function', feature_category: :tooling do
  let(:utils_path) { File.expand_path('../../../scripts/utils.sh', __dir__) }
  let(:tmp_dir) { Dir.mktmpdir }
  # Plays CI_REPOSITORY_URL, the remote that a detached pipeline fetches the base from.
  let(:origin_dir) { File.join(tmp_dir, 'origin') }
  # Plays the clone-gitlab-repo artifact, checked out on the MR source branch.
  let(:clone_dir) { File.join(tmp_dir, 'clone') }
  let(:unreachable_remote) { File.join(tmp_dir, 'does-not-exist') }

  let(:git_env) do
    {
      'GIT_CONFIG_GLOBAL' => '/dev/null', 'GIT_CONFIG_SYSTEM' => '/dev/null',
      'GIT_AUTHOR_NAME' => 'Test', 'GIT_AUTHOR_EMAIL' => 'test@example.com',
      'GIT_COMMITTER_NAME' => 'Test', 'GIT_COMMITTER_EMAIL' => 'test@example.com'
    }
  end

  let!(:origin_base_sha) do
    git_init(origin_dir)
    git_commit(origin_dir, 'base').tap do
      git_commit(origin_dir, 'later')
      # The GitLab remote allows fetching a commit by SHA.
      git(origin_dir, 'config', 'uploadpack.allowAnySHA1InWant', 'true')
    end
  end

  let!(:clone_head_sha) do
    git_init(clone_dir)
    git_commit(clone_dir, 'clone-head').tap do
      # `git branch --force` refuses to move the current branch, so sit on the source branch like CI does.
      git(clone_dir, 'checkout', '-q', '-b', 'mr-source')
    end
  end

  after do
    FileUtils.rm_rf(tmp_dir)
  end

  def git_init(dir)
    FileUtils.mkdir_p(dir)
    git(dir, 'init', '-q', '-b', 'master')
  end

  def git(dir, *args)
    stdout, stderr, status = Open3.capture3(git_env, 'git', '-C', dir, *args)
    raise "git #{args.join(' ')} failed: #{stderr}" unless status.success?

    stdout.strip
  end

  def git_commit(dir, message)
    git(dir, 'commit', '-q', '--allow-empty', '-m', message)
    git(dir, 'rev-parse', 'HEAD')
  end

  # Runs the function the way GitLab Runner runs job scripts: in a subshell with `set -eo pipefail`.
  # `sleep` is stubbed so that `retry` does not wait between failed fetches.
  def run_function(env, function = 'set_migrations_diff_base')
    ci_env = {
      'CI_MERGE_REQUEST_TARGET_BRANCH_NAME' => 'master',
      'CI_REPOSITORY_URL' => origin_dir,
      'CI_MERGE_REQUEST_TARGET_BRANCH_SHA' => nil,
      'CI_MERGE_REQUEST_DIFF_BASE_SHA' => nil
    }

    Open3.capture3(
      git_env.merge(ci_env, env), 'bash', '-c',
      "set -eo pipefail\n. '#{utils_path}'\nsleep() { :; }\n#{function}",
      chdir: clone_dir
    )
  end

  describe 'fetch_merge_request_diff_base' do
    it 'prints only the diff base SHA, also when it fetches it' do
      stdout, stderr, status = run_function(
        { 'CI_MERGE_REQUEST_DIFF_BASE_SHA' => origin_base_sha }, 'fetch_merge_request_diff_base'
      )

      expect(status).to be_success, stderr
      expect(stdout).to eq("#{origin_base_sha}\n")
      expect(git(clone_dir, 'rev-parse', "#{origin_base_sha}^{commit}")).to eq(origin_base_sha)
    end
  end

  context 'when the fetch fails' do
    it 'fails without moving the target branch' do
      _, _, status = run_function(
        'CI_MERGE_REQUEST_DIFF_BASE_SHA' => origin_base_sha,
        'CI_REPOSITORY_URL' => unreachable_remote
      )

      expect(status).not_to be_success
      expect(git(clone_dir, 'rev-parse', 'master')).to eq(clone_head_sha)
    end
  end

  context 'in a merged results pipeline' do
    it 'points the target branch at the target branch SHA, which is in the clone, without fetching' do
      _, stderr, status = run_function(
        'CI_MERGE_REQUEST_TARGET_BRANCH_SHA' => clone_head_sha,
        'CI_MERGE_REQUEST_DIFF_BASE_SHA' => origin_base_sha,
        'CI_REPOSITORY_URL' => unreachable_remote
      )

      expect(status).to be_success, stderr
      expect(stderr).to include('nothing to fetch')
      expect(git(clone_dir, 'rev-parse', 'master')).to eq(clone_head_sha)
    end
  end

  context 'in a detached pipeline' do
    it 'fetches the diff base SHA and points the target branch at it' do
      _, stderr, status = run_function('CI_MERGE_REQUEST_DIFF_BASE_SHA' => origin_base_sha)

      expect(status).to be_success, stderr
      expect(stderr).to include("Fetching diff base #{origin_base_sha}")
      expect(git(clone_dir, 'rev-parse', 'master')).to eq(origin_base_sha)
    end
  end

  context 'when neither base variable is set' do
    it 'fails with an explanatory message' do
      _, stderr, status = run_function({})

      expect(status).not_to be_success
      expect(stderr).to include('Cannot determine the diff base')
    end
  end
end
