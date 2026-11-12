# frozen_string_literal: true

module QA
  module Tools
    module Ci
      class E2eTestSelector
        include Helpers

        # @param changed_files [Array<String>] paths relative to the repository root
        def initialize(changed_files)
          @changed_files = changed_files
        end

        # @return [Array<String>] spec paths relative to the qa directory
        def execute
          logger.info("Fetching tests to execute based on backend code paths mapping")

          unless code_paths_map
            logger.warn("Failed to obtain code mappings for test selection!")
            return []
          end

          tests_from_frontend_mapping = []
          tests_from_backend_mapping = matching_specs(code_paths_map)

          if QA::Runtime::Env.frontend_selective_execution_enabled?
            tests_from_frontend_mapping = tests_from_frontend_code_paths_mapping
          end

          (tests_from_frontend_mapping + tests_from_backend_mapping).uniq
        end

        private

        attr_reader :changed_files

        def tests_from_frontend_code_paths_mapping
          logger.info("Fetching tests from frontend code paths mapping")

          unless frontend_code_paths_map
            logger.warn("Failed to obtain code mappings for test selection!")
            return []
          end

          matching_specs(frontend_code_paths_map) { |path| path.sub(%r{^.*/gitlab/}, '') }
        end

        def matching_specs(map)
          clean_map = map.each_with_object(Hash.new { |h, k| h[k] = [] }) do |(example_id, mappings), hsh|
            name = example_id.gsub("./", "").split(":").first
            mappings = mappings.map { |path| yield(path) } if block_given?

            hsh[name] = (hsh[name] + mappings).uniq
          end

          clean_map
            .select { |_test, mappings| changed_files.any? { |file| mappings.include?(file) } }
            .keys
        end

        # @return [Hash]
        def code_paths_map
          @code_paths_map ||= QA::Tools::Ci::CodePathsMapping.new.import("master", "e2e-test-on-cng")
        end

        # @return [Hash]
        def frontend_code_paths_map
          @frontend_code_paths_map ||= QA::Tools::Ci::CodePathsMapping
                                         .new.import("master", "e2e-test-on-cng",
                                           file_name: "js-coverage-by-example-merged-pipeline")
        end
      end
    end
  end
end
