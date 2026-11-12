# frozen_string_literal: true

require 'rspec-parameterized'

require 'gitlab/diff/all'

require_relative 'support/position_formatters_shared_examples'

RSpec.configure do |config|
  # Matches the monolith (spec/support/rspec.rb). RSpec defaults this to true,
  # which locks a mutex on every `let` read.
  # See https://gitlab.com/gitlab-org/gitlab/-/issues/379686
  config.threadsafe = false

  # Enable flags like --only-failures and --next-failure
  config.example_status_persistence_file_path = ".rspec_status"

  # Disable RSpec exposing methods globally on `Module` and `main`
  config.disable_monkey_patching!

  config.expect_with :rspec do |c|
    c.syntax = :expect
  end

  config.before do
    Gitlab::Diff.configure do |diff|
      diff.diff_line_code = ->(file_path, new_pos, old_pos) { "#{file_path}_#{old_pos}_#{new_pos}" }
      diff.binary_notice = ->(text) { text.to_s.start_with?('Binary files') }
      diff.serialize_line = ->(line) { line.to_hash }
    end
  end
end
