# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Packages::Npm::CreateTagService, feature_category: :package_registry do
  let(:package) { create(:npm_package) }
  let(:tag_name) { 'test-tag' }

  describe '#execute' do
    subject(:result) { described_class.new(package, tag_name).execute }

    shared_examples 'it creates the tag' do
      it { expect { result }.to change { Packages::Tag.count }.by(1) }

      it 'adds tag to the package and reports a change', :aggregate_failures do
        expect(result).to be_success
        expect(result.payload[:tag].name).to eq(tag_name)
        expect(result.payload[:changed]).to be(true)
        expect(package.reload.tags).to match_array([result.payload[:tag]])
      end
    end

    context 'with no existing tag name' do
      it_behaves_like 'it creates the tag'
    end

    context 'with exisiting tag name' do
      let!(:package_tag2) { create(:packages_tag, package: package2, name: tag_name) }

      context 'on package with different name' do
        let!(:package2) { create(:npm_package, project: package.project) }

        it_behaves_like 'it creates the tag'
      end

      context 'on same package with different version' do
        let!(:package2) { create(:npm_package, project: package.project, name: package.name, version: '5.0.0-testing') }

        it { expect { result }.to not_change { Packages::Tag.count } }

        it 'moves the tag to the package and reports a change', :aggregate_failures do
          expect(result.payload[:tag]).to eq(package_tag2)
          expect(result.payload[:changed]).to be(true)
          expect(package.reload.tags).to match_array([package_tag2])
          expect(package2.reload.tags).to be_empty
        end
      end

      context 'on the same package' do
        let(:package2) { package }

        it 'returns the existing tag and reports no change', :aggregate_failures do
          expect(result).to be_success
          expect(result.payload[:tag]).to eq(package_tag2)
          expect(result.payload[:changed]).to be(false)
        end
      end
    end
  end
end
