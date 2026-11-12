# frozen_string_literal: true

require "pathname"

module QA
  module Tools
    module Ci
      # Determine specific qa specs or paths to execute based on changes
      class QaChanges
        include Helpers

        QA_PATTERN = %r{^qa/}
        SPEC_PATTERN = %r{^qa/qa/specs/features/\S+_spec\.rb}
        DEPENDENCY_PATTERN = Regexp.union(
          /_VERSION/,
          /Gemfile\.lock/,
          /yarn\.lock/,
          /Dockerfile\.assets/
        )

        def initialize(mr_diff)
          @mr_diff = mr_diff
        end

        # Specific specs to run
        #
        # @return [Array]
        def qa_tests(from_code_path_mapping: false)
          return [] if mr_diff.empty? || dependency_changes
          return changed_specs if only_spec_changes?
          return E2eTestSelector.new(changed_files).execute if from_code_path_mapping

          []
        end

        # Qa framework changes
        #
        # @return [Boolean]
        def framework_changes?
          return false if mr_diff.empty?
          return false if only_spec_changes?

          changed_files
            # TODO: expand pattern to other non spec paths that shouldn't trigger full suite
            .select { |file_path| file_path.match?(QA_PATTERN) && !file_path.match?(SPEC_PATTERN) }
            .any?
        end

        # Only quarantine changes
        #
        # @return [Boolean]
        def quarantine_changes?
          return false if mr_diff.empty?
          return false if mr_diff.any? { |change| change[:new_file] || change[:deleted_file] }

          files_count = 0
          specs_count = 0
          quarantine_specs_count = 0

          mr_diff.each do |change|
            path = change[:path]
            next if File.directory?(File.expand_path("../#{path}", QA::Runtime::Path.qa_root))

            files_count += 1
            next unless path.match?(SPEC_PATTERN) && path.end_with?('_spec.rb')

            specs_count += 1
            quarantine_specs_count += 1 if change[:diff].match?(/^\+.*,? quarantine:/)
          end

          return false if specs_count == 0
          return true if quarantine_specs_count == specs_count && quarantine_specs_count == files_count

          false
        end

        # All changes are spec removals
        #
        # @return [Boolean]
        def only_spec_removal?
          return false if mr_diff.empty?

          only_spec_changes? && mr_diff.all? { |change| change[:deleted_file] }
        end

        # All changes are changes to non e2e specs
        #
        # @return [Boolean]
        def only_changes_to_non_e2e_spec_files?
          return false if mr_diff.empty?

          mr_diff.all? { |change| change[:path].start_with?("spec/", "ee/spec/") }
        end

        # Change files in merge request
        #
        # @return [Array<String>]
        def changed_files
          @changed_files ||= mr_diff.pluck(:path)
        end

        private

        # @return [Array]
        attr_reader :mr_diff

        # Changed spec files
        #
        # @return [Array, nil]
        def changed_specs
          mr_diff
            .reject { |change| change[:deleted_file] }
            .map { |change| change[:path].delete_prefix("qa/") } # make paths relative to qa directory
        end

        # Are the changed files only qa specs?
        #
        # @return [Boolean] whether the changes files are only qa specs
        def only_spec_changes?
          changed_files.all? { |file_path| file_path =~ SPEC_PATTERN }
        end

        # Are the changed files only outside the qa directory?
        #
        # @return [Boolean] whether the changes files are outside of qa directory
        def non_qa_changes?
          changed_files.none? { |file_path| file_path =~ QA_PATTERN }
        end

        # Changes to gitlab dependencies
        #
        # @return [Boolean]
        def dependency_changes
          changed_files.any? { |file| file.match?(DEPENDENCY_PATTERN) }
        end
      end
    end
  end
end
