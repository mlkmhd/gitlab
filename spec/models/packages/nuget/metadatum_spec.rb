# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Packages::Nuget::Metadatum, feature_category: :package_registry do
  it { is_expected.to be_a Packages::Nuget::VersionNormalizable }

  describe 'relationships' do
    it { is_expected.to belong_to(:package).class_name('Packages::Nuget::Package').inverse_of(:nuget_metadatum) }
  end

  describe 'validations' do
    it { is_expected.to validate_presence_of(:package) }
    it { is_expected.to validate_presence_of(:authors) }
    it { is_expected.to validate_length_of(:authors).is_at_most(described_class::MAX_AUTHORS_LENGTH) }
    it { is_expected.to validate_presence_of(:description) }
    it { is_expected.to validate_length_of(:description).is_at_most(described_class::MAX_DESCRIPTION_LENGTH) }
    it { is_expected.to validate_presence_of(:normalized_version) }

    %i[license_url project_url icon_url].each do |url|
      describe "##{url}" do
        it { is_expected.to allow_value('http://sandbox.com').for(url) }
        it { is_expected.to allow_value('https://sandbox.com').for(url) }
        it { is_expected.not_to allow_value('123').for(url) }
        it { is_expected.not_to allow_value('sandbox.com').for(url) }
        it { is_expected.to validate_length_of(url).is_at_most(described_class::MAX_URL_LENGTH) }
      end

      describe "skip #{url} validation" do
        before do
          stub_application_setting(nuget_skip_metadata_url_validation: true)
        end

        it { is_expected.not_to allow_value('123').for(url) }
        it { is_expected.not_to allow_value('sandbox.com').for(url) }
      end

      describe '#ensure_nuget_package_type', :aggregate_failures do
        subject(:nuget_metadatum) { build(:nuget_metadatum) }

        it 'builds a valid metadatum' do
          expect { nuget_metadatum }.not_to raise_error
          expect(nuget_metadatum).to be_valid
        end

        context 'with a different package type' do
          let(:package) { build(:generic_package) }

          it 'raises the error' do
            expect { build(:nuget_metadatum, package: package) }.to raise_error(ActiveRecord::AssociationTypeMismatch)
          end
        end
      end
    end
  end

  describe 'delegations' do
    it { is_expected.to delegate_method(:version).to(:package).with_prefix }
  end

  describe '.normalized_version_in' do
    let_it_be(:nuget_metadatums) { create_list(:nuget_metadatum, 2) }

    subject { described_class.normalized_version_in(nuget_metadatums.first.normalized_version) }

    it { is_expected.to contain_exactly(nuget_metadatums.first) }

    context 'with a stored version of 3.0.0' do
      using RSpec::Parameterized::TableSyntax

      let_it_be(:nuget_metadatum) { create(:nuget_metadatum, package: create(:nuget_package, version: '3.0.0')) }

      subject { described_class.normalized_version_in(version) }

      where(:version, :expected) do
        '3.0.0'           | [ref(:nuget_metadatum)]
        '3.0.0.0'         | [ref(:nuget_metadatum)]
        '3.0'             | [ref(:nuget_metadatum)]
        '3.0.0+meta'      | [ref(:nuget_metadatum)]
        '3.0.0.00+Build5' | [ref(:nuget_metadatum)]
        '3.0.0.1'         | []
        '3.0.0-rc'        | []
        '+'               | []
      end

      with_them do
        it { is_expected.to match_array(expected) }
      end
    end

    context 'with a prerelease label' do
      using RSpec::Parameterized::TableSyntax

      let_it_be(:beta) { create(:nuget_metadatum, package: create(:nuget_package, version: '1.0-beta')) }
      let_it_be(:beta_zero) { create(:nuget_metadatum, package: create(:nuget_package, version: '1.0-beta.0')) }
      let_it_be(:rc_one) { create(:nuget_metadatum, package: create(:nuget_package, version: '1.0-rc.1')) }
      let_it_be(:rc_one_zero) { create(:nuget_metadatum, package: create(:nuget_package, version: '1.0-rc.1.0')) }
      let_it_be(:beta_seven) { create(:nuget_metadatum, package: create(:nuget_package, version: '1.0.0-beta.7abc')) }

      subject { described_class.normalized_version_in(version) }

      # The stored normalized version still reads the dots of a prerelease label as version
      # parts: 1.0-beta is stored as 1.0-beta.0, and 1.0-rc.1.0 as 1.0-rc.1.
      where(:version, :expected) do
        '1.0-beta'          | []
        '1.0-beta.0'        | [ref(:beta), ref(:beta_zero)]
        '1.0-rc.1'          | [ref(:rc_one), ref(:rc_one_zero)]
        '1.0-rc.1.0'        | []
        '1.0.0-beta.7abc'   | [ref(:beta_seven)]
        '1.0.0-BETA.7abc'   | [ref(:beta_seven)]
        '1.0.0-beta.007abc' | []
      end

      with_them do
        it { is_expected.to match_array(expected) }
      end
    end
  end

  describe 'callbacks' do
    describe '#set_normalized_version' do
      using RSpec::Parameterized::TableSyntax

      let_it_be_with_reload(:nuget_metadatum) { create(:nuget_metadatum) }

      where(:version, :normalized_version) do
        '1.0'                     | '1.0.0'
        '1.0.0.0'                 | '1.0.0'
        '0.1'                     | '0.1.0'
        '1.0.7+r3456'             | '1.0.7'
        '8.0.0.00+RC.54'          | '8.0.0'
        '1.0.0-Alpha'             | '1.0.0-alpha'
        '1.0.00-RC-02'            | '1.0.0-rc-02'
        '8.0.000-preview.0.546.0' | '8.0.0-preview.0.546.0'
        '0.1.0-dev.37+0999370'    | '0.1.0-dev.37'
        '1.2.3'                   | '1.2.3'
      end

      with_them do
        it 'saves the normalized version' do
          nuget_metadatum.package.update_column(:version, version)
          nuget_metadatum.save!

          expect(nuget_metadatum.normalized_version).to eq(normalized_version)
        end
      end
    end
  end
end
