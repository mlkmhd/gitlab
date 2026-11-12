# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Gitlab::Diff::Configuration do
  subject(:configuration) { described_class.new }

  it 'passes the reader arguments through to a callable' do
    configuration.diff_line_code = ->(path, new_pos, old_pos) { [path, new_pos, old_pos] }

    expect(configuration.diff_line_code('a.rb', 2, 1)).to eq(['a.rb', 2, 1])
  end

  it 'returns a plain value as given' do
    configuration.binary_notice = false

    expect(configuration.binary_notice?('Binary files a and b differ')).to be(false)
  end

  it 'raises a configuration error naming the input when it was never set' do
    expect { configuration.serialize_line(nil) }
      .to raise_error(Gitlab::Diff::MissingConfigurationError, /`serialize_line` is not configured/)
  end
end
