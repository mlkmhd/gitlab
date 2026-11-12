# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Security::ScannedResourcesService, '#execute', feature_category: :vulnerability_management do
  before do
    stub_licensed_features(sast: true, dependency_scanning: true, container_scanning: true, dast: true)
  end

  let_it_be(:project) { create(:project) }
  let_it_be(:pipeline) { create(:ci_pipeline, :success, project: project) }

  before_all do
    create(:ci_build, :success, name: 'dast_job', pipeline: pipeline, project: project) do |job|
      create(:ee_ci_job_artifact, :dast, job: job, project: project)
    end
    create(:ci_build, :success, name: 'sast_job', pipeline: pipeline, project: project) do |job|
      create(:ee_ci_job_artifact, :sast, job: job, project: project)
    end
  end

  context 'The pipeline has security builds' do
    context 'Report types are requested' do
      subject(:result) { described_class.new(pipeline, %w[sast dast]).execute }

      it 'only returns the requested scans with the scanned resources', :aggregate_failures do
        expect(result.keys).to contain_exactly('sast', 'dast')
        expect(result['sast']).to be_empty
        expect(result['dast'].length).to eq(6)
        expect(result['dast']).to include(
          {
            'url' => 'http://api-server/',
            'request_method' => 'GET'
          }
        )
      end
    end
  end

  context 'Report types that can have scanned resources are requested with ones that cannot' do
    subject(:result) { described_class.new(pipeline, %w[sast dast]).execute }

    it 'only parses the report types that can have scanned resources', :aggregate_failures do
      allow(Gitlab::Ci::Parsers).to receive(:fabricate!).and_call_original

      expect(result['sast']).to be_empty
      expect(result['dast']).not_to be_empty
      expect(Gitlab::Ci::Parsers).to have_received(:fabricate!)
        .with(satisfy { |type| type.to_s == 'dast' }, any_args)
      expect(Gitlab::Ci::Parsers).not_to have_received(:fabricate!)
        .with(satisfy { |type| type.to_s == 'sast' }, any_args)
    end
  end

  context 'API fuzzing is requested with a report type that cannot have scanned resources' do
    let_it_be(:api_fuzzing_pipeline) { create(:ci_pipeline, :success, project: project) }

    before_all do
      create(:ci_build, :success, name: 'api_fuzzing_job', pipeline: api_fuzzing_pipeline, project: project) do |job|
        create(:ee_ci_job_artifact, :api_fuzzing, job: job, project: project)
      end
      create(:ci_build, :success, name: 'sast_job', pipeline: api_fuzzing_pipeline, project: project) do |job|
        create(:ee_ci_job_artifact, :sast, job: job, project: project)
      end
    end

    before do
      stub_licensed_features(api_fuzzing: true, sast: true)
    end

    subject(:result) { described_class.new(api_fuzzing_pipeline, %w[api_fuzzing sast]).execute }

    it 'parses the API fuzzing report but not the SAST report', :aggregate_failures do
      allow(Gitlab::Ci::Parsers).to receive(:fabricate!).and_call_original

      expect(result).to eq({ 'api_fuzzing' => [], 'sast' => [] })
      expect(Gitlab::Ci::Parsers).to have_received(:fabricate!)
        .with(satisfy { |type| type.to_s == 'api_fuzzing' }, any_args)
      expect(Gitlab::Ci::Parsers).not_to have_received(:fabricate!)
        .with(satisfy { |type| type.to_s == 'sast' }, any_args)
    end
  end

  context 'Only report types that cannot have scanned resources are requested' do
    subject(:result) { described_class.new(pipeline, %w[sast dependency_scanning]).execute }

    it 'does not parse any security reports', :aggregate_failures do
      expect(pipeline).not_to receive(:security_reports)

      expect(result).to eq({ 'sast' => [], 'dependency_scanning' => [] })
    end
  end

  context 'A limited number of scanned resources are requested' do
    subject(:result) { described_class.new(pipeline, %w[dast], 2).execute }

    it 'returns the scanned resources' do
      expect(result['dast'].length).to eq(2)
    end
  end

  context 'The Pipeline has no security builds' do
    let_it_be(:pipeline) { create(:ci_pipeline, :success, project: project) }

    subject(:result) { described_class.new(pipeline, %w[sast dast]).execute }

    it 'returns no scanned resources for each requested report type' do
      is_expected.to match(
        a_hash_including('sast' => [], 'dast' => [])
      )
    end
  end

  context 'Pipeline is nil' do
    subject(:result) { described_class.new(nil, %w[sast dast]).execute }

    it 'returns no scanned resources for each requested report type' do
      is_expected.to match(
        a_hash_including('sast' => [], 'dast' => [])
      )
    end
  end
end
