# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Packages::Swift::Package, feature_category: :package_registry do
  it { is_expected.to be_a Packages::Package }

  describe 'validations' do
    describe '#name' do
      # The identifier is `scope.name`, and each half has its own rules in
      # sections 3.6.1 and 3.6.2 of the registry specification.
      it { is_expected.to allow_value('mona.LinkedList').for(:name) }
      it { is_expected.to allow_value('mona.Linked_List').for(:name) }
      it { is_expected.to allow_value('mo-na.Linked-List').for(:name) }
      it { is_expected.to allow_value('MONA.LINKEDLIST').for(:name) }

      it { is_expected.not_to allow_value('LinkedList').for(:name) }
      it { is_expected.not_to allow_value('mona.LinkedList.extra').for(:name) }
      it { is_expected.not_to allow_value('-mona.LinkedList').for(:name) }
      it { is_expected.not_to allow_value('mona-.LinkedList').for(:name) }
      it { is_expected.not_to allow_value('mo--na.LinkedList').for(:name) }
      it { is_expected.not_to allow_value('mo_na.LinkedList').for(:name) }
      it { is_expected.not_to allow_value('mona._LinkedList').for(:name) }
      it { is_expected.not_to allow_value('mona.Linked__List').for(:name) }
      it { is_expected.not_to allow_value("mona.#{'a' * 101}").for(:name) }
      it { is_expected.not_to allow_value("#{'a' * 40}.LinkedList").for(:name) }
    end

    describe '#version' do
      it { is_expected.to allow_value('1.0.0').for(:version) }
      it { is_expected.to allow_value('1.0.0-beta.1').for(:version) }

      it { is_expected.not_to allow_value('1.0').for(:version) }
      it { is_expected.not_to allow_value('v1.0.0').for(:version) }
    end
  end

  describe '.with_identifier' do
    let_it_be(:project) { create(:project) }
    let_it_be(:package) { create(:swift_package, project: project, name: 'mona.LinkedList') }
    let_it_be(:other_package) { create(:swift_package, project: project, name: 'mona.HashMap') }

    it 'finds the package by scope and name' do
      expect(described_class.with_identifier('mona', 'LinkedList')).to contain_exactly(package)
    end

    # Section 3.6: scopes and names are both case-insensitive.
    it 'matches regardless of case' do
      expect(described_class.with_identifier('MONA', 'linkedlist')).to contain_exactly(package)
    end

    it 'is empty when nothing matches' do
      expect(described_class.with_identifier('mona', 'Missing')).to be_empty
    end
  end
end
