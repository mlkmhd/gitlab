# frozen_string_literal: true

require 'fileutils'
require 'openssl'
require 'securerandom'
require 'tmpdir'

require 'gitaly'

# Starts a private Gitaly for the specs, from the binaries in `GITALY_BIN_DIR`.
# It defaults to the monolith's `tmp/tests/gitaly/_build/bin`, which
# `scripts/gitaly-test-build` builds locally and the parent pipeline's
# `setup-test-env` job publishes in CI. The server gets its own socket, storage
# and token, so it never touches a Gitaly the monolith's specs are using.
module GitalyServer
  STORAGE = 'default'
  BOOT_TIMEOUT = 30

  class << self
    attr_reader :address, :token

    def bin_dir
      ENV.fetch('GITALY_BIN_DIR') { File.expand_path('../../../../tmp/tests/gitaly/_build/bin', __dir__) }
    end

    def available?
      File.executable?(File.join(bin_dir, 'gitaly'))
    end

    def start
      @root = Dir.mktmpdir('gitlab-git-gitaly')
      # Unix socket paths are limited to about 100 bytes.
      @runtime_dir = Dir.mktmpdir('gg', '/tmp')
      @address = "unix:#{File.join(@runtime_dir, 'gitaly.socket')}"
      @token = SecureRandom.hex(16)

      config = write_config
      log = File.join(@root, 'gitaly.log')
      @pid = Process.spawn({ 'GITALY_TESTING_NO_GIT_HOOKS' => '1' },
        File.join(bin_dir, 'gitaly'), config, out: log, err: log)

      wait_until_serving(log)
    end

    def stop
      return unless @pid

      Process.kill('TERM', @pid)
      Process.wait(@pid)
    rescue Errno::ESRCH, Errno::ECHILD
      nil
    ensure
      @pid = nil
      FileUtils.rm_rf([@root, @runtime_dir].compact)
    end

    def stub(service)
      Gitaly.const_get(:"#{service}Service", false)::Stub.new(address, :this_channel_is_insecure)
    end

    def metadata
      { metadata: { 'authorization' => "Bearer #{auth_token}" } }
    end

    private

    # The v2 token format that `Gitlab::GitalyClient.token` builds.
    def auth_token
      issued_at = Time.now.to_i.to_s
      hmac = OpenSSL::HMAC.hexdigest(OpenSSL::Digest.new('SHA256'), token, issued_at)

      "v2.#{hmac}.#{issued_at}"
    end

    def write_config
      storage = File.join(@root, 'repositories')
      shell = File.join(@root, 'gitlab-shell')
      FileUtils.mkdir_p([storage, shell, File.join(@root, 'log')])
      File.write(File.join(shell, '.gitlab_shell_secret'), SecureRandom.hex(16))

      path = File.join(@root, 'config.toml')
      File.write(path, <<~TOML)
        bin_dir = "#{bin_dir}"
        runtime_dir = "#{@runtime_dir}"
        socket_path = "#{@address.delete_prefix('unix:')}"

        [auth]
        token = "#{token}"

        [git]
        use_bundled_binaries = true

        [gitlab]
        url = "http://localhost"

        [gitlab-shell]
        dir = "#{shell}"

        [logging]
        dir = "#{File.join(@root, 'log')}"
        level = "warn"

        [[storage]]
        name = "#{STORAGE}"
        path = "#{storage}"
      TOML
      path
    end

    def now
      Process.clock_gettime(Process::CLOCK_MONOTONIC)
    end

    def wait_until_serving(log)
      deadline = now + BOOT_TIMEOUT

      begin
        stub(:Server).server_info(Gitaly::ServerInfoRequest.new, **metadata)
      rescue GRPC::BadStatus
        raise "Gitaly did not start within #{BOOT_TIMEOUT}s:\n#{File.read(log)}" if now > deadline

        sleep 0.1
        retry
      end
    end
  end
end
