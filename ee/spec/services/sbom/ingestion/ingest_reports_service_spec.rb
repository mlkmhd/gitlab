# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Sbom::Ingestion::IngestReportsService, feature_category: :dependency_management do
  let_it_be(:group) { create(:group) }
  let_it_be(:project) { create(:project, :public, group: group) }
  let_it_be(:pipeline) { build_stubbed(:ci_pipeline, project: project) }
  let_it_be(:reports) { create_list(:ci_reports_sbom_report, 4) }

  let(:wrapper) { instance_double(Gitlab::Ci::Reports::Sbom::Reports) }

  subject(:execute) { described_class.execute(pipeline) }

  before do
    allow(wrapper).to receive(:reports).and_return(reports)
    allow(pipeline).to receive(:sbom_reports).with(self_and_project_descendants: true).and_return(wrapper)
  end

  describe '#execute' do
    context 'when lease is taken' do
      include ExclusiveLeaseHelpers

      let(:lease_key) { Sbom::Ingestion.project_lease_key(pipeline.project.id) }

      before do
        stub_const("#{described_class}::LEASE_TRY_AFTER", 0.01)
        stub_exclusive_lease_taken(lease_key)
      end

      it 'does not permit parallel execution on the same project' do
        expect { execute }.to raise_error(Gitlab::ExclusiveLeaseHelpers::FailedToObtainLockError)
      end
    end

    context 'when a report is invalid' do
      let_it_be(:invalid_report) { create(:ci_reports_sbom_report, :invalid) }
      let_it_be(:reports) { [invalid_report] + create_list(:ci_reports_sbom_report, 4) }

      it 'does not process the invalid report' do
        execute

        error_messages = pipeline
          .sbom_report_ingestion_errors
          .flatten
          .pluck("message")

        expect(error_messages).to eq(invalid_report.errors.flatten)
      end
    end

    context 'when a report source is container_scanning_for_registry' do
      let_it_be(:registry_sources) { create(:ci_reports_sbom_source, :container_scanning_for_registry) }
      let_it_be(:reports) { [create(:ci_reports_sbom_report, source: registry_sources)] }

      it 'uses ContainerScanningForRegistry strategy' do
        expect_next_instance_of(Sbom::Ingestion::ExecutionStrategy::ContainerScanningForRegistry) do |instance|
          expect(instance).to receive(:execute)
        end

        execute
      end
    end

    context 'when the components of a report carry a source file' do
      let(:strategy) { instance_double(Sbom::Ingestion::ExecutionStrategy::Default, execute: nil) }

      let(:components) do
        [
          build(:ci_reports_sbom_component, path: 'core/pom.xml'),
          build(:ci_reports_sbom_component, path: 'foo/pom.xml'),
          build(:ci_reports_sbom_component, path: 'foo/pom.xml')
        ]
      end

      let(:path_report) do
        Gitlab::Ci::Reports::Sbom::Report.new(third_party_sbom_support: true).tap do |report|
          components.each { |component| report.add_component(component) }
        end
      end

      let(:reports) { [path_report] }

      before do
        allow(Sbom::Ingestion::ExecutionStrategy::Default).to receive(:new).and_return(strategy)
      end

      it 'ingests one report for each source file' do
        execute

        expect(Sbom::Ingestion::ExecutionStrategy::Default).to have_received(:new) do |ingested_reports, *|
          expect(ingested_reports.map { |report| [report.source.input_file_path, report.components.size] })
            .to contain_exactly(['core/pom.xml', 1], ['foo/pom.xml', 2])
        end
      end

      context 'when another report has no component with a source file' do
        let(:other_report) { build(:ci_reports_sbom_report) }
        let(:reports) { [path_report, other_report] }

        it 'ingests the other report as it is' do
          execute

          expect(Sbom::Ingestion::ExecutionStrategy::Default).to have_received(:new) do |ingested_reports, *|
            expect(ingested_reports.size).to eq(3)
            expect(ingested_reports.last).to equal(other_report)
          end
        end
      end

      context 'when the report has no third-party SBOM support' do
        let(:path_report) do
          Gitlab::Ci::Reports::Sbom::Report.new.tap do |report|
            components.each { |component| report.add_component(component) }
          end
        end

        it 'ingests the report as it is' do
          execute

          expect(Sbom::Ingestion::ExecutionStrategy::Default)
            .to have_received(:new).with([path_report], project, pipeline)
        end
      end
    end

    context 'when two reports list the same package at the same source file' do
      let_it_be(:pipeline) { create(:ee_ci_pipeline, project: project) }

      let(:reports) do
        Array.new(2) do
          component = build(:ci_reports_sbom_component, name: 'lib', version: '1.0', path: 'core/pom.xml')
          Gitlab::Ci::Reports::Sbom::Report.new(third_party_sbom_support: true).tap { |r| r.add_component(component) }
        end
      end

      it 'ingests both reports' do
        allow(Sbom::Ingestion::IngestReportService).to receive(:execute).and_call_original

        execute

        expect(Sbom::Ingestion::IngestReportService).to have_received(:execute).twice
      end

      it 'stores one row for the package at that source file' do
        expect { execute }.to change { Sbom::Occurrence.where(project_id: project.id).count }.by(1)
        expect(Sbom::Occurrence.last.input_file_path).to eq('core/pom.xml')
      end
    end

    context 'when there are no container_scanning_for_registry sources' do
      it 'uses Default strategy' do
        expect_next_instance_of(Sbom::Ingestion::ExecutionStrategy::Default) do |instance|
          expect(instance).to receive(:execute)
        end

        execute
      end
    end

    context 'with third-party SBOMs' do
      let(:job) do
        create(:ee_ci_build, :success, pipeline: create(:ee_ci_pipeline, project: project), project: project)
      end

      let(:sbom_artifact) do
        create(:ee_ci_job_artifact, job: job, project: project, file_type: :cyclonedx, file_format: :gzip,
          file: fixture_file_upload(
            Rails.root.join("ee/spec/fixtures/sbom/third_party/#{sbom_fixture}.cdx.json.gz"), 'application/x-gzip'))
      end

      let(:pipeline) { sbom_artifact.job.pipeline }
      let(:project_occurrences) { Sbom::Occurrence.where(project_id: project.id) }

      before do
        allow(pipeline).to receive(:sbom_reports).and_call_original
      end

      context 'with a generic SBOM' do
        let(:sbom_fixture) { 'generic' }

        where(:third_party_sbom_support, :library_path) do
          [
            [true, '3rd Party Input File Path Unknown'],
            [false, nil]
          ]
        end

        with_them do
          before do
            stub_feature_flags(third_party_sbom_support: third_party_sbom_support)
          end

          it 'lists each library at the default location only when the flag is enabled' do
            execute

            expect(pipeline.reload.sbom_report_ingestion_errors).to be_nil
            expect(project_occurrences).to contain_exactly(
              have_attributes(component_name: 'commons-io/commons-io', input_file_path: library_path,
                package_manager: nil, ancestors: []),
              have_attributes(component_name: 'lodash', input_file_path: library_path,
                package_manager: nil, ancestors: [])
            )
          end
        end

        context 'when third_party_sbom_support is enabled only for another project' do
          before do
            stub_feature_flags(third_party_sbom_support: build_stubbed(:project))
          end

          it 'lists each library with no path' do
            execute

            expect(pipeline.reload.sbom_report_ingestion_errors).to be_nil
            expect(project_occurrences).to contain_exactly(
              have_attributes(component_name: 'commons-io/commons-io', input_file_path: nil,
                package_manager: nil, ancestors: []),
              have_attributes(component_name: 'lodash', input_file_path: nil, package_manager: nil, ancestors: [])
            )
          end
        end
      end

      context 'with a library that has no package URL' do
        let(:sbom_fixture) { 'library_without_purl' }

        it 'lists the library at the default location' do
          execute

          expect(pipeline.reload.sbom_report_ingestion_errors).to be_nil
          expect(project_occurrences).to contain_exactly(
            have_attributes(component_name: 'no-purl-lib', input_file_path: '3rd Party Input File Path Unknown')
          )
        end
      end

      context 'with a library whose package URL type is not supported' do
        let(:sbom_fixture) { 'unsupported_purl_type' }

        it 'skips that library without an error' do
          execute

          expect(pipeline.reload.sbom_report_ingestion_errors).to be_nil
          expect(project_occurrences).to contain_exactly(
            have_attributes(component_name: 'commons-io/commons-io',
              input_file_path: '3rd Party Input File Path Unknown'),
            have_attributes(component_name: 'lodash', input_file_path: '3rd Party Input File Path Unknown')
          )
        end
      end

      context 'when an image SBOM lists an operating system package' do
        let(:sbom_fixture) { 'operating_system_package' }

        where(:third_party_sbom_support, :library_path) do
          [
            [true, '3rd Party Input File Path Unknown'],
            [false, nil]
          ]
        end

        with_them do
          before do
            stub_feature_flags(third_party_sbom_support: third_party_sbom_support)
          end

          it 'lists the package with no path and no source, and the libraries at the default location only when ' \
            'the flag is enabled' do
            execute

            expect(pipeline.reload.sbom_report_ingestion_errors).to be_nil
            expect(project_occurrences).to contain_exactly(
              have_attributes(component_name: 'bash', input_file_path: nil, package_manager: nil, ancestors: [],
                source: nil),
              have_attributes(component_name: 'commons-io/commons-io', input_file_path: library_path),
              have_attributes(component_name: 'lodash', input_file_path: library_path)
            )
          end
        end
      end

      context 'when the SBOM is from GitLab container scanning without an image tag' do
        let(:sbom_fixture) { 'container_scanning_without_image_tag' }

        shared_examples 'lists the packages with no path' do
          it 'lists the packages with no path' do
            execute

            expect(pipeline.reload.sbom_report_ingestion_errors).to be_nil
            expect(project_occurrences).to contain_exactly(
              have_attributes(component_name: 'commons-io/commons-io', input_file_path: nil,
                package_manager: nil, ancestors: []),
              have_attributes(component_name: 'lodash', input_file_path: nil, package_manager: nil, ancestors: [])
            )
          end
        end

        context 'when the feature flag is enabled' do
          before do
            stub_feature_flags(third_party_sbom_support: true)
          end

          it_behaves_like 'lists the packages with no path'
        end

        context 'when the feature flag is disabled' do
          before do
            stub_feature_flags(third_party_sbom_support: false)
          end

          it_behaves_like 'lists the packages with no path'
        end
      end

      context 'when the SBOM is invalid' do
        let(:sbom_fixture) { 'invalid_component_version' }

        shared_examples 'rejects the SBOM with the schema errors' do
          it 'rejects the SBOM with the schema errors and lists no rows' do
            execute

            expect(pipeline.reload.sbom_report_ingestion_errors).to contain_exactly(
              contain_exactly(
                a_hash_including('message' => "property '/components/0/version' is invalid: error_type=minLength")
              )
            )
            expect(project_occurrences).to be_empty
          end
        end

        context 'when the feature flag is enabled' do
          before do
            stub_feature_flags(third_party_sbom_support: true)
          end

          it_behaves_like 'rejects the SBOM with the schema errors'
        end

        context 'when the feature flag is disabled' do
          before do
            stub_feature_flags(third_party_sbom_support: false)
          end

          it_behaves_like 'rejects the SBOM with the schema errors'
        end
      end

      context 'when the SBOM is from the GitLab dependency scanning analyzer' do
        shared_examples 'lists the rows at the location the SBOM records' do
          it 'lists the rows at the location the SBOM records' do
            execute

            expect(pipeline.reload.sbom_report_ingestion_errors).to be_nil
            expect(project_occurrences).to contain_exactly(
              have_attributes(component_name: 'commons-io/commons-io', input_file_path: 'core/pom.xml',
                package_manager: 'maven', ancestors: []),
              have_attributes(component_name: 'lodash', input_file_path: 'core/pom.xml',
                package_manager: 'maven', ancestors: [])
            )
          end
        end

        context 'with the properties the analyzer writes' do
          let(:sbom_fixture) { 'gitlab_dependency_scanning' }

          context 'when the feature flag is enabled' do
            before do
              stub_feature_flags(third_party_sbom_support: true)
            end

            it_behaves_like 'lists the rows at the location the SBOM records'
          end

          context 'when the feature flag is disabled' do
            before do
              stub_feature_flags(third_party_sbom_support: false)
            end

            it_behaves_like 'lists the rows at the location the SBOM records'
          end
        end

        context 'with the properties other generators write besides those of the analyzer' do
          let(:sbom_fixture) { 'gitlab_dependency_scanning_with_other_generator_properties' }

          context 'when the feature flag is enabled' do
            before do
              stub_feature_flags(third_party_sbom_support: true)
            end

            it_behaves_like 'lists the rows at the location the SBOM records'
          end

          context 'when the feature flag is disabled' do
            before do
              stub_feature_flags(third_party_sbom_support: false)
            end

            it_behaves_like 'lists the rows at the location the SBOM records'
          end
        end
      end
    end
  end
end
