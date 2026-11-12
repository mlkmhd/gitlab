# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Security::ScanResultPolicies::DependencyFilter, feature_category: :security_policy_management do
  include DependencyFilterSbomHelpers

  let_it_be(:project) { create(:project) }

  let(:lockfile) { 'requirements.txt' }
  let(:findings) do
    [
      finding('unchanged', 'requests', '2.31.0'),
      finding('bumped', 'requests', '2.32.0'),
      finding('other-lockfile', 'requests', '2.31.0', file: 'service-b/requirements.txt')
    ]
  end

  let(:target_pipeline) { pipeline_with(direct: [%w[requests 2.31.0]]) }
  let(:source_pipeline) { create(:ci_pipeline, project: project) }
  let(:target_pipeline_ids) { [target_pipeline&.id].compact }
  let(:source_pipeline_ids) { [source_pipeline.id] }
  let(:dependency_change) { nil }
  let(:dependency_type) { nil }

  subject(:filtered) do
    described_class.new(source_pipeline_ids: source_pipeline_ids, target_pipeline_ids: target_pipeline_ids)
      .filter(findings, dependency_change: dependency_change, dependency_type: dependency_type)
  end

  def pipeline_with(**sbom)
    create(:ci_pipeline, project: project).tap { |pipeline| create_sbom_build(pipeline, **sbom) }
  end

  def finding(uuid, name, version, file: lockfile)
    [uuid, { 'file' => file, 'dependency' => { 'package' => { 'name' => name }, 'version' => version } }]
  end

  context 'without settings' do
    it { is_expected.to contain_exactly('unchanged', 'bumped', 'other-lockfile') }
  end

  context 'with dependency_change: introduced' do
    let(:dependency_change) { 'introduced' }

    it 'matches components whose lockfile, name or version differ from the target' do
      expect(filtered).to contain_exactly('bumped', 'other-lockfile')
    end

    context 'without a target pipeline' do
      let(:target_pipeline) { nil }

      it { is_expected.to contain_exactly('unchanged', 'bumped', 'other-lockfile') }
    end

    context 'when the target pipeline has no SBOM' do
      let(:target_pipeline) { create(:ci_pipeline, project: project) }

      it { is_expected.to contain_exactly('unchanged', 'bumped', 'other-lockfile') }
    end

    context 'when only one of several target pipelines has the SBOM' do
      let(:target_pipeline_ids) { [create(:ci_pipeline, project: project).id, target_pipeline.id] }

      it { is_expected.to contain_exactly('bumped', 'other-lockfile') }
    end
  end

  context 'with dependency_change: unchanged' do
    let(:dependency_change) { 'unchanged' }

    it { is_expected.to contain_exactly('unchanged') }

    context 'without a target pipeline' do
      let(:target_pipeline) { nil }

      it { is_expected.to be_empty }
    end
  end

  context 'with dependency_type' do
    let(:findings) do
      [
        finding('direct', 'requests', '2.31.0'),
        finding('transitive', 'urllib3', '2.0.0'),
        finding('not-in-sbom', 'idna', '3.4')
      ]
    end

    let(:source_pipeline) { pipeline_with(direct: [%w[requests 2.31.0]], transitive: [%w[urllib3 2.0.0]]) }

    context 'when direct' do
      let(:dependency_type) { 'direct' }

      it { is_expected.to contain_exactly('direct', 'not-in-sbom') }
    end

    context 'when transitive' do
      let(:dependency_type) { 'transitive' }

      it { is_expected.to contain_exactly('transitive', 'not-in-sbom') }
    end

    context 'when the source SBOM has no dependency graph' do
      let(:dependency_type) { 'direct' }
      let(:source_pipeline) { pipeline_with(direct: [%w[requests 2.31.0], %w[urllib3 2.0.0]], graph: false) }

      it { is_expected.to contain_exactly('direct', 'transitive', 'not-in-sbom') }
    end

    context 'when one report lists a package as both direct and transitive' do
      let(:dependency_type) { 'transitive' }
      let(:findings) { [finding('both', 'urllib3', '2.0.0')] }
      let(:source_pipeline) do
        pipeline_with(direct: [%w[requests 2.31.0], %w[urllib3 2.0.0]], transitive: [%w[urllib3 2.0.0]])
      end

      it { is_expected.to contain_exactly('both') }

      context 'when direct' do
        let(:dependency_type) { 'direct' }

        it { is_expected.to contain_exactly('both') }
      end
    end

    context 'when another source report lists the transitive package as direct' do
      let(:dependency_type) { 'transitive' }
      let(:source_pipeline) do
        pipeline_with(direct: [%w[requests 2.31.0]], transitive: [%w[urllib3 2.0.0]]).tap do |pipeline|
          create_sbom_build(pipeline, direct: [%w[urllib3 2.0.0]])
        end
      end

      it { is_expected.to contain_exactly('transitive', 'not-in-sbom') }
    end

    context 'when another source report gives a graph-less package a type' do
      let(:dependency_type) { 'direct' }
      let(:source_pipeline) do
        pipeline_with(direct: [%w[requests 2.31.0]], graph: false).tap do |pipeline|
          create_sbom_build(pipeline, direct: [%w[flask 3.0.0]], transitive: [%w[requests 2.31.0], %w[urllib3 2.0.0]])
        end
      end

      it { is_expected.to contain_exactly('direct', 'not-in-sbom') }
    end

    context 'when only another source pipeline has the SBOM' do
      let(:dependency_type) { 'direct' }
      let(:source_pipeline_ids) { [create(:ci_pipeline, project: project).id, source_pipeline.id] }

      it { is_expected.to contain_exactly('direct', 'not-in-sbom') }
    end

    context 'when combined with dependency_change' do
      let(:dependency_type) { 'direct' }
      let(:dependency_change) { 'introduced' }

      it { is_expected.to contain_exactly('not-in-sbom') }
    end
  end

  context 'when the target SBOM report has no source' do
    let(:dependency_change) { 'unchanged' }
    let(:findings) do
      [finding('with-lockfile', 'requests', '2.31.0'), finding('no-file', 'requests', '2.31.0', file: nil)]
    end

    let(:target_pipeline) { pipeline_with(direct: [%w[requests 2.31.0]], input_file: nil) }

    it 'only matches findings without a lockfile' do
      expect(filtered).to contain_exactly('no-file')
    end
  end

  context 'when the target SBOM report is invalid' do
    let(:dependency_change) { 'unchanged' }
    let(:findings) { [finding('unchanged', 'requests', '2.31.0')] }

    let(:target_pipeline) do
      create(:ci_pipeline, project: project).tap do |pipeline|
        create(:ee_ci_build, :success, :with_invalid_cyclonedx_report, pipeline: pipeline)
      end
    end

    it 'ignores its components' do
      expect(filtered).to be_empty
    end
  end

  context 'when a UUID has several finding rows' do
    let(:dependency_change) { 'introduced' }
    let(:findings) { [finding('uuid', 'requests', '2.31.0'), finding('uuid', 'requests', '2.32.0')] }

    it { is_expected.to eq(['uuid']) }
  end

  it 'runs the same queries however many findings are filtered' do
    count_queries = ->(findings) do
      filter = described_class.new(source_pipeline_ids: [source_pipeline.id],
        target_pipeline_ids: target_pipeline_ids)

      ActiveRecord::QueryRecorder.new do
        filter.filter(findings, dependency_change: 'introduced', dependency_type: 'direct')
      end.count
    end

    introduced = findings.drop(1) # the dependency_type check only runs for introduced components
    count_queries.call(introduced) # warms one-off caches

    expect(count_queries.call(introduced * 5)).to eq(count_queries.call(introduced.first(1)))
  end

  it 'runs the same queries however many pipelines are read' do
    count_queries = ->(pipelines) do
      filter = described_class.new(source_pipeline_ids: pipelines.map(&:id), target_pipeline_ids: pipelines.map(&:id))

      ActiveRecord::QueryRecorder.new do
        filter.filter(findings, dependency_change: 'introduced', dependency_type: 'direct')
      end.count
    end

    pipelines = [
      pipeline_with(direct: [%w[requests 2.31.0]]),
      pipeline_with(direct: [%w[requests 2.32.0]]),
      create(:ci_pipeline, project: project)
    ]
    count_queries.call(pipelines) # warms one-off caches

    expect(count_queries.call(pipelines)).to eq(count_queries.call(pipelines.first(1)))
  end
end
