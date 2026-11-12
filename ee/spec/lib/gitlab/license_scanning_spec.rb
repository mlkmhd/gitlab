# frozen_string_literal: true

require "spec_helper"

RSpec.describe ::Gitlab::LicenseScanning, feature_category: :software_composition_analysis do
  let_it_be(:project) { create(:project, :repository, create_branch: "license_scanning_branch") }

  describe "#scanner_for_project" do
    subject(:scanner) { described_class.scanner_for_project(project) }

    let_it_be(:pipeline) { create(:ee_ci_pipeline, :with_cyclonedx_report, project: project) }
    let_it_be(:latest_pipeline) { nil }

    context "when project only has pipelines with a sbom report" do
      it "returns an sbom scanner" do
        expect(scanner).to be_a_kind_of(::Gitlab::LicenseScanning::SbomScanner)
      end

      context "with default ref" do
        it "contains a pipeline" do
          expect(scanner.pipeline).to eq(pipeline)
        end
      end

      context "with provided ref" do
        subject(:scanner) { described_class.scanner_for_project(project, "license_scanning_branch") }

        let_it_be(:pipeline_2) do
          create(:ee_ci_pipeline, :with_cyclonedx_report, project: project, ref: "license_scanning_branch")
        end

        it "contains a pipeline" do
          expect(scanner.pipeline).to eq(pipeline_2)
        end
      end
    end

    context "when project does not have a pipeline with cyclonedx report" do
      let_it_be(:latest_pipeline) { create(:ee_ci_pipeline, :with_license_scanning_report, project: project) }

      it "returns an sbom scanner" do
        expect(scanner).to be_a_kind_of(::Gitlab::LicenseScanning::SbomScanner)
      end
    end
  end

  describe "#scanner_for_pipeline" do
    subject(:scanner) { described_class.scanner_for_pipeline(project, pipeline) }

    context "when pipeline has only an sbom report" do
      let_it_be(:pipeline) { create(:ee_ci_pipeline, :with_cyclonedx_report, project: project) }

      it "returns an sbom scanner" do
        is_expected.to be_a_kind_of(::Gitlab::LicenseScanning::SbomScanner)
      end

      it "returns a pipeline" do
        expect(scanner.pipeline).to eq(pipeline)
      end
    end

    context "when the sbom report is only in a child pipeline" do
      let_it_be(:pipeline) { create(:ee_ci_pipeline, :success, project: project) }
      let_it_be(:child_pipeline) { create(:ee_ci_pipeline, :success, child_of: pipeline, project: project) }

      before_all do
        create(:ee_ci_build, :success, :cyclonedx_with_license, pipeline: child_pipeline, project: project)
      end

      it "ignores the child pipeline by default" do
        expect(scanner.has_data?).to be(false)
      end

      it "includes the child pipeline when requested" do
        expect(described_class.scanner_for_pipeline(project, pipeline, self_and_project_descendants: true).has_data?)
          .to be(true)
      end
    end

    context "when project does not have a pipeline with cyclonedx report" do
      let_it_be(:pipeline) do
        create(:ee_ci_pipeline, :with_license_scanning_report, project: project)
      end

      it "returns an sbom scanner" do
        is_expected.to be_a_kind_of(::Gitlab::LicenseScanning::SbomScanner)
      end

      it "returns a pipeline" do
        expect(scanner.pipeline).to eq(pipeline)
      end
    end

    context "with user scoping" do
      let_it_be(:pipeline) { create(:ee_ci_pipeline, :with_cyclonedx_report, project: project) }
      let_it_be(:user) { create(:user) }

      it "defaults the scoping user to the unscoped sentinel" do
        expect(::Gitlab::LicenseScanning::SbomScanner).to receive(:new)
          .with(project, pipeline, described_class::UNSCOPED, self_and_project_descendants: false).and_call_original

        described_class.scanner_for_pipeline(project, pipeline)
      end

      it "threads the given user through to the scanner" do
        expect(::Gitlab::LicenseScanning::SbomScanner).to receive(:new)
          .with(project, pipeline, user, self_and_project_descendants: false).and_call_original

        described_class.scanner_for_pipeline(project, pipeline, user)
      end
    end
  end
end
