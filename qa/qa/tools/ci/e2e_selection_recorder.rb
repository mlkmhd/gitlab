# frozen_string_literal: true

require 'gitlab_quality/test_tooling'
require 'timeout'

module QA
  module Tools
    module Ci
      # Saves each selection so its accuracy can be measured later
      class E2eSelectionRecorder
        include Helpers

        TABLE_NAME = 'e2e_selection_runs'
        # The client's 600s default could hold up the E2E child pipeline
        INSERT_TIMEOUT_SECONDS = 30

        # @param pipeline_tier [String] the pipeline::tier-N label
        # @param changed_files [Array<String>] paths relative to the repository root
        # @param selected_specs [Array<String>] spec paths relative to the qa directory
        def initialize(pipeline_tier:, changed_files:, selected_specs:, clickhouse_client: nil)
          @pipeline_tier = pipeline_tier
          @changed_files = changed_files
          @selected_specs = selected_specs
          @clickhouse_client = clickhouse_client
        end

        def record
          Timeout.timeout(INSERT_TIMEOUT_SECONDS) { clickhouse_client.insert_json_data(TABLE_NAME, [row]) }
        rescue StandardError => e
          logger.warn("Failed to record E2E selection in ClickHouse: #{e.message}")
        end

        private

        attr_reader :pipeline_tier, :changed_files, :selected_specs

        def row
          {
            timestamp: Time.now.utc.strftime('%Y-%m-%d %H:%M:%S.%6N'),
            ci_project_path: ENV.fetch('CI_PROJECT_PATH'),
            ci_pipeline_id: ENV.fetch('CI_PIPELINE_ID').to_i,
            ci_job_id: ENV.fetch('CI_JOB_ID').to_i,
            ci_merge_request_iid: ENV.fetch('CI_MERGE_REQUEST_IID', 0).to_i,
            head_sha: head_sha,
            base_sha: ENV.fetch('CI_MERGE_REQUEST_DIFF_BASE_SHA', ''),
            pipeline_tier: pipeline_tier.to_s,
            changed_files: changed_files,
            # The table stores paths from the repository root
            selected_specs: selected_specs.map { |spec| "qa/#{spec}" }
          }
        end

        def head_sha
          source_sha = ENV.fetch('CI_MERGE_REQUEST_SOURCE_BRANCH_SHA', '')
          source_sha.empty? ? ENV.fetch('CI_COMMIT_SHA') : source_sha
        end

        def clickhouse_client
          @clickhouse_client ||= GitlabQuality::TestTooling::ClickHouse::Client.new(
            url: ENV.fetch('GLCI_DA_CLICKHOUSE_URL'),
            database: ENV.fetch('GLCI_CLICKHOUSE_CODE_COVERAGE_DB'),
            username: ENV.fetch('GLCI_CLICKHOUSE_METRICS_USERNAME'),
            password: ENV.fetch('GLCI_CLICKHOUSE_METRICS_PASSWORD')
          )
        end
      end
    end
  end
end
