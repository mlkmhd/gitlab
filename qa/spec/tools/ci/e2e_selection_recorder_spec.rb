# frozen_string_literal: true

RSpec.describe QA::Tools::Ci::E2eSelectionRecorder, feature_category: :tooling do
  include QA::Support::Helpers::StubEnv

  subject(:recorder) do
    described_class.new(
      pipeline_tier: "pipeline::tier-3",
      changed_files: ["lib/model.rb"],
      selected_specs: ["qa/specs/features/api/test_spec.rb"],
      clickhouse_client: clickhouse_client
    )
  end

  let(:clickhouse_client) do
    instance_double(GitlabQuality::TestTooling::ClickHouse::Client, insert_json_data: nil)
  end

  before do
    stub_env('CI_PROJECT_PATH', 'gitlab-org/gitlab')
    stub_env('CI_PIPELINE_ID', '100')
    stub_env('CI_JOB_ID', '200')
    stub_env('CI_MERGE_REQUEST_IID', '300')
    stub_env('CI_MERGE_REQUEST_SOURCE_BRANCH_SHA', 'head-sha')
    stub_env('CI_MERGE_REQUEST_DIFF_BASE_SHA', 'base-sha')
  end

  it "inserts one row with spec paths from the repository root" do
    recorder.record

    expect(clickhouse_client).to have_received(:insert_json_data).with(
      "e2e_selection_runs",
      [a_hash_including(
        ci_project_path: "gitlab-org/gitlab",
        ci_pipeline_id: 100,
        ci_job_id: 200,
        ci_merge_request_iid: 300,
        head_sha: "head-sha",
        base_sha: "base-sha",
        pipeline_tier: "pipeline::tier-3",
        changed_files: ["lib/model.rb"],
        selected_specs: ["qa/qa/specs/features/api/test_spec.rb"]
      )]
    )
  end

  context "without a merge request source branch SHA" do
    before do
      stub_env('CI_MERGE_REQUEST_SOURCE_BRANCH_SHA', '')
      stub_env('CI_COMMIT_SHA', 'commit-sha')
    end

    it "uses the commit SHA as the head SHA" do
      recorder.record

      expect(clickhouse_client).to have_received(:insert_json_data)
        .with("e2e_selection_runs", [a_hash_including(head_sha: "commit-sha")])
    end
  end

  context "when a CI variable is missing" do
    let(:logger) { instance_double(Logger, warn: nil) }

    before do
      allow(Gitlab::QA::TestLogger).to receive(:logger).and_return(logger)
      allow(ENV).to receive(:fetch).with('CI_PIPELINE_ID').and_raise(KeyError, 'key not found: "CI_PIPELINE_ID"')
    end

    it "logs a warning and skips the insert", :aggregate_failures do
      expect { recorder.record }.not_to raise_error
      expect(logger).to have_received(:warn).with(/CI_PIPELINE_ID/)
      expect(clickhouse_client).not_to have_received(:insert_json_data)
    end
  end

  context "when the insert fails" do
    let(:logger) { instance_double(Logger, warn: nil) }

    before do
      allow(Gitlab::QA::TestLogger).to receive(:logger).and_return(logger)
      allow(clickhouse_client).to receive(:insert_json_data).and_raise(StandardError, "connection refused")
    end

    it "logs a warning instead of raising" do
      expect { recorder.record }.not_to raise_error
      expect(logger).to have_received(:warn).with(/connection refused/)
    end
  end

  context "when the insert takes too long" do
    let(:logger) { instance_double(Logger, warn: nil) }

    before do
      stub_const("#{described_class}::INSERT_TIMEOUT_SECONDS", 0.01)
      allow(Gitlab::QA::TestLogger).to receive(:logger).and_return(logger)
      allow(clickhouse_client).to receive(:insert_json_data) { sleep 1 }
    end

    it "gives up and logs a warning" do
      expect { recorder.record }.not_to raise_error
      expect(logger).to have_received(:warn).with(/Failed to record E2E selection/)
    end
  end
end
