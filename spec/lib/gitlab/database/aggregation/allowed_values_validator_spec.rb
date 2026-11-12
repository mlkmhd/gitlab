# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Gitlab::Database::Aggregation::AllowedValuesValidator, feature_category: :value_stream_management do
  describe '.allowed?' do
    using RSpec::Parameterized::TableSyntax

    where(:allowed, :value, :expected) do
      %w[a b]                                  | 'a'     | true
      %w[a b]                                  | 'c'     | false
      [/\Afoo_\d+\z/]                          | 'foo_1' | true
      [/\Afoo_\d+\z/]                          | 'foo_x' | false
      [Gitlab::UntrustedRegexp.new('\Abar\z')] | 'bar'   | true
      ['a', /\Ab\d\z/]                         | 'b1'    | true
      (0.0..1.0)                               | 0.5     | true
      (0.0..1.0)                               | 1.5     | false
    end

    with_them do
      it { expect(described_class.allowed?(allowed, value)).to eq(expected) }
    end
  end

  describe '#validate' do
    let(:part_class) do
      Struct.new(:raw_values, :instance_key) do
        include ActiveModel::Validations

        def self.name
          'Part'
        end
      end
    end

    let(:validator) { described_class.new(attributes: [:raw_values], in: %w[opened merged]) }

    it 'adds no error when every value is allowed' do
      part = part_class.new(%w[opened merged], 'state')

      validator.validate(part)

      expect(part.errors).to be_empty
    end

    it 'names each invalid value once' do
      part = part_class.new(%w[merged typo typo other], 'state')

      validator.validate(part)

      expect(part.errors.to_a).to contain_exactly('Invalid value(s) for filter `state`: typo, other')
    end

    it 'requires in:' do
      expect { described_class.new(attributes: [:raw_values]) }.to raise_error(ArgumentError, ':in is required')
    end
  end
end
