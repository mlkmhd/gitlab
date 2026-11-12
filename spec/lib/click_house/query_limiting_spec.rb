# frozen_string_literal: true

require 'spec_helper'

RSpec.describe ClickHouse::QueryLimiting, feature_category: :database do
  describe '.rule' do
    let(:matching_rule) { Module.new { def self.applies?(_context) = true } }
    let(:other_rule) { Module.new { def self.applies?(_context) = false } }

    it 'returns the first matching rule' do
      stub_const("#{described_class}::RULES", [other_rule, matching_rule])

      expect(described_class.rule).to eq(matching_rule)
    end

    it 'returns NoLimit when no rule matches' do
      stub_const("#{described_class}::RULES", [other_rule])

      expect(described_class.rule).to eq(described_class::NoLimit)
      expect(described_class.rule).to have_attributes(type: 'none', settings: {})
    end
  end
end
