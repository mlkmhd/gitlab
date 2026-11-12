# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Gitlab::Ci::Parsers::Sbom::Normalizer, feature_category: :dependency_management do
  let(:default_path) { '3rd Party Input File Path Unknown' }
  let(:data) { { 'components' => components } }

  let(:commons_io) do
    {
      'type' => 'library',
      'bom-ref' => 'pkg:maven/commons-io/commons-io@2.4',
      'name' => 'commons-io',
      'version' => '2.4',
      'purl' => 'pkg:maven/commons-io/commons-io@2.4'
    }
  end

  let(:lodash) do
    {
      'type' => 'library',
      'bom-ref' => 'pkg:npm/lodash@4.17.21',
      'name' => 'lodash',
      'version' => '4.17.21',
      'purl' => 'pkg:npm/lodash@4.17.21'
    }
  end

  let(:components) { [commons_io, lodash] }

  subject(:entries) { described_class.new(data).entries }

  context 'when the SBOM records no source file' do
    it 'gives each component the default location' do
      expect(entries.map { |entry| entry.data['name'] }).to eq(%w[commons-io lodash])
      expect(entries.map(&:path)).to all(eq(default_path))
    end

    it 'keeps the component data as it is' do
      expect(entries.map(&:data)).to eq(components)
    end
  end

  context 'when the SBOM records an install path instead of a manifest' do
    let(:lodash) do
      super().merge('properties' => [{ 'name' => 'cdx:npm:package:path', 'value' => 'node_modules/lodash' }])
    end

    it 'gives each component the default location' do
      expect(entries.map(&:path)).to all(eq(default_path))
    end
  end

  context 'when the SBOM lists an operating system package' do
    let(:operating_system_package) do
      { 'type' => 'library', 'bom-ref' => 'os', 'name' => 'os-package', 'version' => '1.0', 'purl' => purl }
    end

    let(:components) { [operating_system_package, commons_io] }

    where(
      purl: %w[
        pkg:deb/debian/bash@5.2.15-2+b7?distro=debian-12.15
        pkg:apk/alpine/musl@1.2.5-r3?distro=3.20.10
        pkg:rpm/redhat/glibc@2.34-100.el9?distro=redhat-9.4
        pkg:cbl-mariner/mariner/bash@5.1.8-4.cm2
        pkg:wolfi/wolfi/glibc@2.39-r1
      ]
    )

    with_them do
      it 'gives the package one entry with no path' do
        expect(entries.map { |entry| [entry.data['name'], entry.path] })
          .to contain_exactly(['os-package', nil], ['commons-io', default_path])
      end
    end
  end

  context 'when a component has a package URL that cannot be parsed' do
    let(:components) { [commons_io.merge('purl' => 'pkg:nil')] }

    it 'gives it the default location' do
      expect(entries.map(&:path)).to eq([default_path])
    end
  end

  context 'when the SBOM lists a package twice' do
    let(:components) { [lodash, lodash] }

    it 'gives an entry for each listing' do
      expect(entries.map { |entry| entry.data['name'] }).to eq(%w[lodash lodash])
    end
  end

  context 'when the SBOM has an empty list of components' do
    let(:data) { { 'components' => [] } }

    it { is_expected.to be_empty }
  end

  context 'when the SBOM has no components' do
    let(:data) { {} }

    it { is_expected.to be_empty }
  end
end
