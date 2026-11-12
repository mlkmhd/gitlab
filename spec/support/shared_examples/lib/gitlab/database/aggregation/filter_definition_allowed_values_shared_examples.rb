# frozen_string_literal: true

RSpec.shared_examples 'aggregation filter definition with allowed values' do
  def build_filter(definition, values)
    Gitlab::Database::Aggregation::QueryPlan::Filter.new(
      definition, { identifier: definition.identifier, values: values }, query_plan: nil
    )
  end

  describe 'in:' do
    let(:formatter) { ->(values) { Array.wrap(values) & %w[opened merged] } }
    let(:definition) { described_class.new(:state, :string, nil, in: %w[opened merged], formatter: formatter) }

    it 'is valid when every value is allowed' do
      expect(build_filter(definition, %w[opened merged])).to be_valid
    end

    it 'accepts a single value' do
      expect(build_filter(definition, 'merged')).to be_valid
    end

    it 'lists each unrecognized value once, even when the formatter drops them' do
      filter = build_filter(definition, %w[merged typo typo other])

      expect(filter).not_to be_valid
      expect(filter.errors.to_a).to contain_exactly('Invalid value(s) for filter `state`: typo, other')
    end

    it 'does not validate values when in: is not given' do
      expect(build_filter(described_class.new(:state, :string), %w[anything])).to be_valid
    end

    it 'has no max_size when only in: is given' do
      expect(definition.max_size).to be_nil
    end
  end
end
