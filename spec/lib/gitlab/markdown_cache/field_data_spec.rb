# frozen_string_literal: true

require 'fast_spec_helper'

RSpec.describe Gitlab::MarkdownCache::FieldData do
  subject(:field_data) { described_class.new }

  before do
    field_data[:description] = { project: double('project in context') }
  end

  it 'translates a markdown field name into a html field name' do
    expect(field_data.html_field(:description)).to eq("description_html")
  end

  describe '#key?' do
    specify do
      expect(field_data.key?(:description)).to be_truthy
      expect(field_data.key?(:something_else)).to be_falsy
    end
  end

  describe '#invalidated_by' do
    it 'is empty when the field declares no invalidating columns' do
      expect(field_data.invalidated_by(:description)).to be_empty
    end

    context 'when the field declares invalidating columns' do
      before do
        field_data[:content] = { pipeline: :plain_markdown, invalidated_by: %i[file_name] }
      end

      it 'returns them as column names' do
        expect(field_data.invalidated_by(:content)).to eq(%w[file_name])
      end

      it 'keeps them out of the rendering context' do
        expect(field_data[:content]).to eq(pipeline: :plain_markdown)
      end
    end
  end

  describe '#condition' do
    it 'allows caching when the field declares no condition' do
      expect(field_data.condition(:description).call).to be(true)
    end

    context 'when the field declares a condition' do
      let(:condition) { ->(file_name:) { file_name.end_with?('.md') } }

      before do
        field_data[:content] = { pipeline: :plain_markdown, invalidated_by: %i[file_name], if: condition }
      end

      it 'returns it' do
        expect(field_data.condition(:content)).to be(condition)
      end

      it 'keeps it out of the rendering context' do
        expect(field_data[:content]).to eq(pipeline: :plain_markdown)
      end
    end
  end
end
