# frozen_string_literal: true

module Security
  # Builds the pipelines the agentic analyzer MR comparison specs compare.
  # Expects `project` and `merge_request` to be defined.
  module AgenticAnalyzerScanHelpers
    # A duo_workflow workload pipeline of the BLSA flow at `sha` with a succeeded SAST scan, as the agentic
    # analyzer publishes it. `record: false` leaves out the marker Security::StoreScansService would set when
    # storing the scan.
    def create_agentic_scan_pipeline(sha:, sast_report: false, record: true)
      pipeline = create(:ci_pipeline, :success, project: project, ref: 'refs/workloads/abc123', sha: sha,
        source: :duo_workflow)
      create(:duo_workflows_workload, workload: create(:ci_workload, pipeline: pipeline),
        workflow: create(:duo_workflows_workflow, project: project,
          workflow_definition: Ai::Catalog::FoundationalFlow::BL_SECURITY_FLOW_REFERENCE))
      build_traits = sast_report ? [:success, :sast_report] : [:success]
      build = create(:ci_build, *build_traits, pipeline: pipeline, project: project)
      create(:security_scan, scan_type: :sast, status: :succeeded, build: build, latest: true)
      Security::AgenticAnalyzer.record_scan(pipeline) if record
      pipeline
    end

    # A regular MR head pipeline, optionally with a succeeded scan of `scan_type` (with one finding by default).
    def create_head_pipeline(scan_type: nil, with_finding: true)
      pipeline = create(:ci_pipeline, :success, project: project, ref: merge_request.source_branch,
        sha: merge_request.diff_head_sha)
      merge_request.update!(head_pipeline: pipeline)

      if scan_type
        build = create(:ci_build, :success, pipeline: pipeline, project: project)
        scan = create(:security_scan, scan_type: scan_type, status: :succeeded, build: build, latest: true)
        create(:security_finding, scan: scan, deduplicated: true) if with_finding
      end

      pipeline
    end
  end
end
