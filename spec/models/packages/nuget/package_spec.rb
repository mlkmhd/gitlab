# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Packages::Nuget::Package, feature_category: :package_registry do
  using RSpec::Parameterized::TableSyntax

  describe 'relationships' do
    it { is_expected.to have_many(:installable_nuget_package_files).inverse_of(:package) }
    it { is_expected.to have_one(:nuget_metadatum).inverse_of(:package) }
    it { is_expected.to have_many(:nuget_symbols).inverse_of(:package) }
  end

  describe 'validations' do
    describe '#name' do
      it 'allows accepted values' do
        is_expected.to allow_values('My.Package', 'My.Package.Mvc', 'MyPackage', 'My.23.Package', 'My23Package',
          'runtime.my-test64.runtime.package.Mvc', 'my_package').for(:name)
      end

      it 'does not allow unaccepted values' do
        is_expected.not_to allow_values('My/package', '../../../my_package', '%2e%2e%2fmy_package').for(:name)
      end
    end

    describe '#version' do
      it 'allows accepted values' do
        is_expected.to allow_values('1.2', '1.2.3', '1.2.3.4', '1.2.3-beta', '1.2.3-alpha.3').for(:version)
      end

      it 'does not allow unaccepted values' do
        is_expected.not_to allow_values('1', '1./2.3', '../../../../../1.2.3', '%2e%2e%2f1.2.3').for(:version)
      end
    end
  end

  describe '.with_nuget_version_or_normalized_version' do
    let_it_be(:nuget_package) { create(:nuget_package, :with_metadatum, version: '1.0.7+r3456') }

    subject { described_class.with_nuget_version_or_normalized_version(version, with_normalized: with_normalized) }

    where(:version, :with_normalized, :expected) do
      '1.0.7'       | true  | [ref(:nuget_package)]
      '1.0.7'       | false | []
      '1.0.7+r3456' | true  | [ref(:nuget_package)]
      '1.0.7+r3456' | false | [ref(:nuget_package)]
      '1.0.7.0'     | false | []
      '1.0.7+other' | false | []
    end

    with_them do
      it { is_expected.to match_array(expected) }
    end
  end

  describe '.order_exact_version_first' do
    let_it_be(:four_parts) { create(:nuget_package, name: 'MyPackage', version: '3.0.0.0', created_at: 2.days.ago) }
    let_it_be(:two_parts) { create(:nuget_package, name: 'MyPackage', version: '3.0', created_at: 1.day.ago) }
    let_it_be(:three_parts) { create(:nuget_package, name: 'MyPackage', version: '3.0.0', created_at: 3.days.ago) }

    subject { described_class.id_in([four_parts, two_parts, three_parts]).order_exact_version_first(version) }

    where(:version, :expected) do
      '3.0.0.0' | [ref(:four_parts), ref(:two_parts), ref(:three_parts)]
      '3.0.0'   | [ref(:three_parts), ref(:two_parts), ref(:four_parts)]
      '3.0'     | [ref(:two_parts), ref(:four_parts), ref(:three_parts)]
      '3.00'    | [ref(:two_parts), ref(:four_parts), ref(:three_parts)]
    end

    with_them do
      it { is_expected.to eq(expected) }
    end

    context 'with build metadata' do
      let_it_be(:prerelease) do
        create(:nuget_package, name: 'MyPackage', version: '2.0.0-alpha', created_at: 3.days.ago)
      end

      let_it_be(:with_metadata) do
        create(:nuget_package, name: 'MyPackage', version: '2.0.0-alpha+Build', created_at: 2.days.ago)
      end

      let_it_be(:longer_label) do
        create(:nuget_package, name: 'MyPackage', version: '2.0.0-alphabet', created_at: 1.day.ago)
      end

      subject { described_class.id_in([prerelease, with_metadata, longer_label]).order_exact_version_first(version) }

      where(:version, :expected) do
        '2.0.0-alpha'       | [ref(:with_metadata), ref(:prerelease), ref(:longer_label)]
        '2.0.0-ALPHA'       | [ref(:with_metadata), ref(:prerelease), ref(:longer_label)]
        '2.0.0-alpha+build' | [ref(:with_metadata), ref(:longer_label), ref(:prerelease)]
      end

      with_them do
        it { is_expected.to eq(expected) }
      end
    end
  end

  describe '.including_dependency_links_with_nuget_metadatum' do
    let_it_be(:package) { create(:nuget_package) }
    let_it_be(:packages_dependency_link) { create(:packages_dependency_link, :with_nuget_metadatum, package: package) }

    subject(:result) { described_class.including_dependency_links_with_nuget_metadatum }

    it 'preloads associations', :aggregate_failures do
      package = result.first
      dependency_link = package.dependency_links.first

      expect(package.association(:dependency_links)).to be_loaded
      expect(dependency_link.association(:dependency)).to be_loaded
      expect(dependency_link.association(:nuget_metadatum)).to be_loaded
    end
  end

  describe '.preload_nuget_metadatum' do
    let_it_be(:package) { create(:nuget_package, :with_metadatum) }

    subject(:result) { described_class.preload_nuget_metadatum }

    it 'preloads nuget metadatum' do
      expect(result.first.association(:nuget_metadatum)).to be_loaded
    end
  end

  describe '.preload_nuget_files' do
    let_it_be(:package) { create(:nuget_package) }

    subject(:result) { described_class.preload_nuget_files }

    it 'preloads installable nuget files' do
      expect(result.first.association(:installable_nuget_package_files)).to be_loaded
    end
  end

  describe '#normalized_nuget_version' do
    let_it_be(:package) { create(:nuget_package, :with_metadatum, version: '1.0') }

    let(:normalized_version) { '1.0.0' }

    subject { package.normalized_nuget_version }

    it { is_expected.to eq(normalized_version) }
  end

  describe '#nuget_file_name' do
    let(:package) { build(:nuget_package, name: 'MyPackage', version: version) }

    subject { package.nuget_file_name(pushed_version, symbol: symbol) }

    where(:version, :pushed_version, :symbol, :expected) do
      '1.0.0'      | '1.0.0'      | false | 'mypackage.1.0.0.nupkg'
      '1.0.0'      | '1.0.0'      | true  | 'mypackage.1.0.0.snupkg'
      '1.0.0'      | '1.0.0.0'    | false | 'mypackage.1.0.0.nupkg'
      '1.0.0.0'    | '1.0'        | true  | 'mypackage.1.0.0.0.snupkg'
      '1.0.0'      | '1.0.0+Meta' | false | 'mypackage.1.0.0.nupkg'
      '1.0-RC.1'   | '1.0-rc.1'   | false | 'mypackage.1.0-rc.1.nupkg'
      '1.0-rc.1.0' | '1.0-rc.1'   | false | 'mypackage.1.0-rc.1.nupkg'
      '1.0-beta'   | '1.0-beta.0' | true  | 'mypackage.1.0-beta.0.snupkg'
    end

    with_them do
      it { is_expected.to eq(expected) }
    end
  end

  describe '.installable_statuses' do
    it 'excludes deprecated because it does not apply to NuGet' do
      expect(described_class.installable_statuses).to contain_exactly(:default, :hidden)
    end
  end

  describe '.installable' do
    let_it_be(:default_package) { create(:nuget_package, :default) }
    let_it_be(:hidden_package) { create(:nuget_package, :hidden) }
    let_it_be(:deprecated_package) { create(:nuget_package, :deprecated) }

    subject { described_class.installable }

    it 'includes default and hidden packages but not deprecated', :aggregate_failures do
      is_expected.to include(default_package, hidden_package)
      is_expected.not_to include(deprecated_package)
    end
  end
end
