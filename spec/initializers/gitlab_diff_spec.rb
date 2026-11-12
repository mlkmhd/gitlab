# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'Gitlab::Diff configuration', feature_category: :source_code_management do
  describe 'diff_line_code' do
    it 'builds the line code with `Gitlab::Git`' do
      expect(Gitlab::Diff.configuration.diff_line_code('files/a.rb', 2, 1))
        .to eq(Gitlab::Git.diff_line_code('files/a.rb', 2, 1))
    end
  end

  describe 'binary_notice' do
    it 'recognises the binary notice with `Gitlab::Git::Diff`' do
      expect(Gitlab::Diff.configuration.binary_notice?('Binary files a/test and b/test differ')).to be(true)
      expect(Gitlab::Diff.configuration.binary_notice?('--- a/test')).to be(false)
    end
  end

  describe 'serialize_line' do
    it 'escapes any HTML special characters in the diff chunk header' do
      line = Gitlab::Diff::Line.new("<input>", "", 0, 0, 0)

      expect(line.as_json[:rich_text]).to eq("&lt;input&gt;")
    end
  end
end
