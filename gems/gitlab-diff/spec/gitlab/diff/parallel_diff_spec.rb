# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Gitlab::Diff::ParallelDiff do
  let(:diff) do
    <<DIFF
--- a/files/ruby/popen.rb
+++ b/files/ruby/popen.rb
@@ -6,12 +6,18 @@ module Popen

   def popen(cmd, path=nil)
     unless cmd.is_a?(Array)
-      raise "System commands must be given as an array of strings"
+      raise RuntimeError, "System commands must be given as an array of strings"
     end

     path ||= Dir.pwd
-    vars = { "PWD" => path }
-    options = { chdir: path }
+
+    vars = {
+      "PWD" => path
+    }
+
+    options = {
+      chdir: path
+    }

     unless File.directory?(path)
       FileUtils.mkdir_p(path)
@@ -19,6 +25,7 @@ module Popen

     @cmd_output = ""
     @cmd_status = 0
+
     Open3.popen3(vars, *cmd, options) do |stdin, stdout, stderr, wait_thr|
       @cmd_output << stdout.read
       @cmd_output << stderr.read
DIFF
  end

  let(:diff_lines) { Gitlab::Diff::Parser.new.parse(diff.lines).to_a }
  let(:diff_file) { Struct.new(:highlighted_diff_lines).new(diff_lines) }

  subject { described_class.new(diff_file) }

  describe '#parallelize' do
    it 'returns an array of arrays containing the parsed diff' do
      expected = [
        # Unchanged lines
        { left: diff_lines[0], right: diff_lines[0] },
        { left: diff_lines[1], right: diff_lines[1] },
        { left: diff_lines[2], right: diff_lines[2] },
        { left: diff_lines[3], right: diff_lines[3] },
        { left: diff_lines[4], right: diff_lines[5] },
        { left: diff_lines[6], right: diff_lines[6] },
        { left: diff_lines[7], right: diff_lines[7] },
        { left: diff_lines[8], right: diff_lines[8] },

        # Changed lines
        { left: diff_lines[9], right: diff_lines[11] },
        { left: diff_lines[10], right: diff_lines[12] },

        # Added lines
        { left: nil, right: diff_lines[13] },
        { left: nil, right: diff_lines[14] },
        { left: nil, right: diff_lines[15] },
        { left: nil, right: diff_lines[16] },
        { left: nil, right: diff_lines[17] },
        { left: nil, right: diff_lines[18] },

        # Unchanged lines
        { left: diff_lines[19], right: diff_lines[19] },
        { left: diff_lines[20], right: diff_lines[20] },
        { left: diff_lines[21], right: diff_lines[21] },
        { left: diff_lines[22], right: diff_lines[22] },
        { left: diff_lines[23], right: diff_lines[23] },
        { left: diff_lines[24], right: diff_lines[24] },
        { left: diff_lines[25], right: diff_lines[25] },

        # Added line
        { left: nil, right: diff_lines[26] },

        # Unchanged lines
        { left: diff_lines[27], right: diff_lines[27] },
        { left: diff_lines[28], right: diff_lines[28] },
        { left: diff_lines[29], right: diff_lines[29] }
      ]

      expect(subject.parallelize).to eq(expected)
    end

    it 'works as a static method' do
      diff_lines = [Gitlab::Diff::Line.new("", 'match', nil, 1, 1)]
      expect(described_class.parallelize(diff_lines)).to eq([
        {
          left: diff_lines[0], right: diff_lines[0]
        }
      ])
    end
  end
end
