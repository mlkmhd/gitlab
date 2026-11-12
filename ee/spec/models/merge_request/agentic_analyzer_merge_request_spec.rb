# frozen_string_literal: true

require 'spec_helper'

RSpec.describe MergeRequest, 'agentic analyzer security comparison', :clean_gitlab_redis_shared_state,
  feature_category: :vulnerability_management do
  include Security::AgenticAnalyzerScanHelpers

  include_context 'with bl_security enabled for the instance'

  let_it_be(:project) { create(:project, :repository) }

  let(:merge_request) { create(:merge_request, source_project: project, target_project: project) }

  before do
    stub_feature_flags(agentic_analyzer_security_ingestion: true)
  end

  describe '#agentic_sast_reports?' do
    before do
      stub_licensed_features(sast: true)
    end

    it 'is true when the scan marker is set and an agentic SAST scan exists' do
      create_agentic_scan_pipeline(sha: merge_request.diff_head_sha, sast_report: true)

      expect(merge_request.agentic_sast_reports?).to be(true)
    end

    context 'when no scan marker was recorded for the commit' do
      before do
        create_agentic_scan_pipeline(sha: merge_request.diff_head_sha, sast_report: true, record: false)
      end

      it 'is false without querying CI or security scans' do
        merge_request.diff_head_sha # warm up the MR diff outside the recorder

        recorder = ActiveRecord::QueryRecorder.new { expect(merge_request.agentic_sast_reports?).to be(false) }

        expect(recorder.log.grep(/p_ci_|security_scans/)).to be_empty
      end
    end
  end

  describe '#has_sast_reports?' do
    before do
      stub_licensed_features(sast: true)
    end

    context 'when only the agentic workload pipeline has a SAST report' do
      before do
        create_agentic_scan_pipeline(sha: merge_request.diff_head_sha, sast_report: true)
      end

      it 'returns true' do
        expect(merge_request.has_sast_reports?).to be(true)
      end

      context 'when agentic analyzer ingestion is disabled' do
        let(:bl_security_enabled_for_instance) { false }

        before do
          stub_feature_flags(agentic_analyzer_security_ingestion: false)
        end

        it 'returns false without resolving the agentic pipeline' do
          expect(Security::AgenticAnalyzer).not_to receive(:scan_pipeline_for)

          expect(merge_request.has_sast_reports?).to be(false)
        end
      end

      context 'when rendered through Rapid Diffs' do
        let!(:older_diff_id) { merge_request.merge_request_diff.id }
        let(:latest_version) { MergeRequests::VersionedMergeRequest.new(merge_request) }
        let(:older_version) do
          MergeRequests::VersionedMergeRequest.new(merge_request, version_params: { diff_id: older_diff_id })
        end

        before do
          merge_request.create_merge_request_diff
          merge_request.reload
        end

        it 'returns true for the latest version only' do
          expect(latest_version.has_sast_reports?).to be(true)
          expect(older_version.has_sast_reports?).to be(false)
        end
      end
    end

    context 'when the regular head pipeline has no SAST report but the agentic workload pipeline does' do
      it 'returns true' do
        create_head_pipeline(scan_type: :dependency_scanning)
        create_agentic_scan_pipeline(sha: merge_request.diff_head_sha, sast_report: true)

        expect(merge_request.has_sast_reports?).to be(true)
      end
    end
  end

  describe 'security comparison delegation' do
    let(:head) { instance_double(Ci::Pipeline) }
    let(:base) { instance_double(Ci::Pipeline) }
    let(:additional_ids) { { additional_head_pipeline_ids: [1] } }
    let(:comparison) do
      instance_double(Security::AgenticAnalyzer::MergeRequestComparison,
        head_pipeline: head, base_pipeline: base, additional_pipeline_ids: additional_ids)
    end

    before do
      allow(Security::AgenticAnalyzer::MergeRequestComparison)
        .to receive(:new).with(merge_request, 'sast').and_return(comparison)
      allow(Security::AgenticAnalyzer::MergeRequestComparison)
        .to receive(:new).with(merge_request, 'dependency_scanning').and_return(comparison)
    end

    it 'delegates #security_comparison_head_pipeline' do
      expect(merge_request.security_comparison_head_pipeline('sast')).to eq(head)
    end

    it 'delegates #comparison_base_pipeline for the security comparison' do
      expect(merge_request.comparison_base_pipeline(Vulnerabilities::CompareSecurityReportsService, 'sast'))
        .to eq(base)
    end

    it 'delegates #security_comparison_additional_pipeline_ids' do
      expect(merge_request.security_comparison_additional_pipeline_ids('sast')).to eq(additional_ids)
    end

    it 'builds one comparison per report type' do
      merge_request.security_comparison_head_pipeline('sast')
      merge_request.comparison_base_pipeline(Vulnerabilities::CompareSecurityReportsService, 'sast')
      merge_request.security_comparison_additional_pipeline_ids('sast')
      merge_request.security_comparison_head_pipeline('dependency_scanning')
      merge_request.security_comparison_additional_pipeline_ids('dependency_scanning')

      expect(Security::AgenticAnalyzer::MergeRequestComparison).to have_received(:new).twice
      expect(Security::AgenticAnalyzer::MergeRequestComparison)
        .to have_received(:new).with(merge_request, 'dependency_scanning').once
    end
  end
end
