# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Gitlab::Ci::Reports::Sbom::Report, feature_category: :dependency_management do
  subject(:report) { described_class.new }

  describe '#valid?' do
    context 'when there are no errors' do
      it { is_expected.to be_valid }
    end

    context 'when report contains errors' do
      before do
        report.add_error('error1')
        report.add_error('error2')
      end

      it { is_expected.not_to be_valid }
    end
  end

  describe '#third_party_sbom_support' do
    it 'is false by default' do
      expect(report.third_party_sbom_support).to be(false)
    end

    it 'is the value the report is created with' do
      expect(described_class.new(third_party_sbom_support: true).third_party_sbom_support).to be(true)
    end
  end

  describe '#third_party?' do
    using RSpec::Parameterized::TableSyntax

    let(:gitlab_property) { { 'name' => 'gitlab:meta:schema_version', 'value' => '1' } }
    let(:other_property) { { 'name' => 'other-generator:property', 'value' => '1' } }
    let(:properties) do
      { none: [], other: [other_property], gitlab: [gitlab_property], both: [other_property, gitlab_property] }
        .fetch(recorded_properties)
    end

    subject(:report) do
      described_class.new(third_party_sbom_support: third_party_sbom_support).tap do |report|
        report.metadata.properties = properties
      end
    end

    where(:third_party_sbom_support, :recorded_properties, :third_party) do
      true  | :none   | true
      true  | :other  | true
      true  | :gitlab | false
      true  | :both   | false
      false | :none   | false
      false | :other  | false
      false | :gitlab | false
    end

    with_them do
      it 'is true only with third-party SBOM support and no property that starts with the GitLab prefix' do
        expect(report.third_party?).to be(third_party)
      end
    end
  end

  describe '#add_error' do
    it 'appends errors to a list' do
      report.add_error('error1')
      report.add_error('error2')

      expect(report.errors).to match_array(%w[error1 error2])
    end
  end

  describe '#set_source' do
    let_it_be(:source, freeze: false) { create(:ci_reports_sbom_source) }

    it 'stores the source' do
      report.set_source(source)

      expect(report.source).to eq(source)
    end
  end

  describe '#add_component' do
    let_it_be(:components, freeze: false) { create_list(:ci_reports_sbom_component, 3) }

    it 'appends components to a list' do
      components.each { |component| report.add_component(component) }

      expect(report.components).to match_array(components)
    end
  end

  describe 'ensure_ancestors!' do
    let_it_be(:components, freeze: false) { create_list(:ci_reports_sbom_component, 3) }

    let(:component_first) { components.first }
    let(:component_last) { components.last }
    let(:expected_value) { { name: component_first.name, version: component_first.version } }

    it 'stores hierachies' do
      components.each { |component| report.add_component(component) }
      report.add_dependency(component_first.ref, component_last.ref)

      report.ensure_ancestors!

      expect(component_last.ancestors).to match_array([expected_value])
    end
  end

  describe '#add_metadata_component' do
    let_it_be(:metadata_component, freeze: false) { create(:ci_reports_sbom_component) }
    let_it_be(:component, freeze: false) { create(:ci_reports_sbom_component) }

    it 'sets empty hash into ancestors' do
      report.set_metadata_component(metadata_component)
      report.add_component(component)
      report.add_dependency(metadata_component.ref, component.ref)

      report.ensure_ancestors!

      expect(component.ancestors).to match_array([{}])
    end
  end

  describe '#split_by_path' do
    let(:first_component) { build(:ci_reports_sbom_component, name: 'first', path: 'core/pom.xml') }
    let(:second_component) { build(:ci_reports_sbom_component, name: 'second', path: 'foo/pom.xml') }
    let(:third_component) { build(:ci_reports_sbom_component, name: 'third', path: 'core/pom.xml') }
    let(:components) { [first_component, second_component, third_component] }

    let(:report) do
      built = build(:ci_reports_sbom_report, source: nil, components: components)
      built.add_dependency(first_component.ref, second_component.ref)
      built
    end

    subject(:split_reports) { report.split_by_path }

    context 'when the components carry no path' do
      let(:components) { build_list(:ci_reports_sbom_component, 2) }

      it 'returns the report itself' do
        expect(split_reports).to contain_exactly(equal(report))
      end
    end

    context 'when the report has no components' do
      let(:components) { [] }

      it 'returns the report itself' do
        expect(split_reports).to contain_exactly(equal(report))
      end
    end

    context 'when the components carry a path' do
      it 'returns one report for each path with the components of that path' do
        expect(split_reports.map { |split| [split.source.input_file_path, split.components.map(&:name)] })
          .to contain_exactly(['core/pom.xml', %w[first third]], ['foo/pom.xml', %w[second]])
      end

      it 'does not return the report itself' do
        expect(split_reports).not_to include(report)
      end

      it 'returns each component once' do
        expect(split_reports.flat_map(&:components)).to match_array(components)
      end

      it 'gives each report a dependency scanning source without a package manager' do
        expect(split_reports.map(&:source)).to all(have_attributes(source_type: :dependency_scanning, packager: nil))
      end

      it 'shares the dependency graph of the report' do
        second_report = split_reports.find { |split| split.components.include?(second_component) }
        second_report.ensure_ancestors!

        expect(second_component.ancestors).to contain_exactly({ name: 'first', version: first_component.version })
      end

      it 'gives each report the metadata and the attributes of the report' do
        expect(split_reports)
          .to all(have_attributes(metadata: report.metadata, sbom_attributes: report.sbom_attributes))
      end

      it 'leaves the report as it is' do
        expect { split_reports }.not_to change { [report.components.dup, report.source, report.errors.dup] }
      end

      context 'when the report has third-party SBOM support' do
        let(:report) do
          described_class.new(third_party_sbom_support: true).tap do |report|
            components.each { |component| report.add_component(component) }
          end
        end

        it 'gives each report the third-party SBOM support of the report' do
          expect(split_reports.map(&:third_party_sbom_support)).to contain_exactly(true, true)
        end
      end

      context 'when the report has an error' do
        let(:report) { build(:ci_reports_sbom_report, :invalid, source: nil, components: components) }

        it 'gives each report the error without sharing the list of errors', :aggregate_failures do
          expect(split_reports).to all(have_attributes(errors: report.errors))
          expect(split_reports.map(&:errors)).not_to include(equal(report.errors))
        end
      end

      context 'when a package is listed at two paths' do
        let(:second_again) do
          build(:ci_reports_sbom_component, name: 'second', ref: second_component.ref, path: 'core/pom.xml')
        end

        let(:components) { [first_component, second_component, third_component, second_again] }

        it 'gives the package the same ancestors at each path' do
          split_reports.each(&:ensure_ancestors!)
          ancestors = split_reports.flat_map do |split|
            split.components.select { |component| component.ref == second_component.ref }.map(&:ancestors)
          end

          expected_ancestors = [{ name: 'first', version: first_component.version }]

          expect(ancestors).to contain_exactly(expected_ancestors, expected_ancestors)
        end
      end
    end

    context 'when only some of the components carry a path' do
      let(:no_path_component) { build(:ci_reports_sbom_component, name: 'no-path') }
      let(:components) { [first_component, no_path_component, third_component] }

      it 'returns the components without a path in a report with the source of the report' do
        expect(split_reports.map { |split| [split.source&.input_file_path, split.components.map(&:name)] })
          .to contain_exactly(['core/pom.xml', %w[first third]], [nil, %w[no-path]])
      end

      it 'returns each component once' do
        expect(split_reports.flat_map(&:components)).to match_array(components)
      end

      context 'when the report has a source' do
        let(:report) { build(:ci_reports_sbom_report, components: components) }

        it 'gives the report of the components without a path that source' do
          expect(split_reports.last.source).to equal(report.source)
        end
      end

      context 'when a component without a path is listed first' do
        let(:components) { [no_path_component, second_component] }

        it 'returns the report of the components without a path last' do
          expect(split_reports.map { |split| split.components.map(&:name) }).to eq([%w[second], %w[no-path]])
        end
      end
    end
  end
end
