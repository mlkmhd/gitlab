# frozen_string_literal: true

module RuboCop
  module Cop
    module Gitlab
      # Limits a block of consecutive comment lines to three lines of prose.
      # See https://docs.gitlab.com/development/code_comments/#keep-comments-short
      #
      # @example
      #   # bad
      #   # Finds a user for the given email.
      #   # Looks up the primary email first.
      #   # Falls back to secondary emails.
      #   # Returns nil when nothing matches.
      #   def find_by_any_email(email); end
      #
      #   # good
      #   # Secondary emails are unconfirmed until verified, so they're checked last.
      #   def find_by_any_email(email); end
      #
      #   # good
      #   # @param email [String]
      #   # @return [User, nil]
      #   def find_by_any_email(email); end
      class CommentLength < RuboCop::Cop::Base
        MSG = 'Comment has %<count>d lines of prose, more than %<max>d. ' \
          'Keep the why and move the rest to the MR or issue. ' \
          'See https://docs.gitlab.com/development/code_comments/#keep-comments-short'

        MAX = 3
        YARD_TAG = /\A#\s*@(option|param|raise|return|see|yield(param|return)?)\b/
        YARD_EXAMPLE = /\A#\s*@example\b/
        EXAMPLE_CODE = /\A#\s{2,}\S/
        SKIP = /\A#(!|#?\s*\z)/

        def on_new_investigation
          exempt_lines = processed_source.ast&.each_node(:class, :module)&.map { |node| node.loc.line } || []

          comment_blocks.each do |block|
            next if exempt_lines.include?(block.last.loc.line + 1)

            count = prose_line_count(block)
            next if count <= MAX

            add_offense(block.last, message: format(MSG, count: count, max: MAX))
          end
        end

        private

        def comment_blocks
          processed_source.comments
            .select { |comment| comment_line?(processed_source.lines[comment.loc.line - 1]) }
            .slice_when { |previous, current| current.loc.line != previous.loc.line + 1 }
        end

        def prose_line_count(block)
          in_example = false

          block.count do |comment|
            text = comment.text

            if skip?(comment)
              false
            elsif text.match?(YARD_EXAMPLE)
              in_example = true
              false
            elsif in_example && text.match?(EXAMPLE_CODE)
              false
            else
              in_example = false
              !text.match?(YARD_TAG)
            end
          end
        end

        def skip?(comment)
          comment.text.match?(SKIP) ||
            DirectiveComment.new(comment).start_with_marker? ||
            MagicComment.parse(comment.text).any?
        end
      end
    end
  end
end
