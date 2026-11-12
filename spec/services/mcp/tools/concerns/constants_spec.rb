# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Mcp::Tools::Concerns::Constants, feature_category: :mcp_server do
  let(:test_class) do
    Class.new do
      include Mcp::Tools::Concerns::Constants
    end
  end

  describe 'VERSIONS' do
    it 'defines version 0.1.0' do
      expect(test_class::VERSIONS[:v0_1_0]).to eq('0.1.0')
    end

    it 'is frozen' do
      expect(test_class::VERSIONS).to be_frozen
    end

    it 'all version values follow semantic versioning pattern' do
      version_pattern = /\A\d+\.\d+\.\d+\z/

      test_class::VERSIONS.each_value do |version|
        expect(version).to match(version_pattern),
          "Expected version '#{version}' to match semantic versioning pattern (e.g., '1.2.3')"
      end
    end
  end

  describe 'MARKDOWN_TEXT_MAX_LENGTH' do
    it 'caps long-form markdown fields at 1,048,576 characters' do
      expect(test_class::MARKDOWN_TEXT_MAX_LENGTH).to eq(1_048_576)
    end
  end
end
