# frozen_string_literal: true

require 'gitlab/git/version'

require_relative 'support/gitaly_server'
require_relative 'support/fixture_repository'

RSpec.configure do |config|
  # Enable flags like --only-failures and --next-failure
  config.example_status_persistence_file_path = ".rspec_status"

  # Disable RSpec exposing methods globally on `Module` and `main`
  config.disable_monkey_patching!

  config.expect_with :rspec do |c|
    c.syntax = :expect
  end

  config.before(:suite) do
    if GitalyServer.available?
      GitalyServer.start
    elsif ENV['CI']
      raise "No Gitaly binaries in #{GitalyServer.bin_dir}. Set GITALY_BIN_DIR."
    end
  end

  config.after(:suite) do
    GitalyServer.stop
  end

  config.before(:each, :gitaly) do
    skip "No Gitaly binaries in #{GitalyServer.bin_dir}. Set GITALY_BIN_DIR." unless GitalyServer.address
  end
end
