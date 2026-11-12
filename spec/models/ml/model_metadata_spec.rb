# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Ml::ModelMetadata, feature_category: :mlops do
  describe 'associations' do
    it { is_expected.to belong_to(:model).required }
    it { is_expected.to validate_length_of(:name).is_at_most(255) }
    it { is_expected.to validate_length_of(:value).is_at_most(5000) }
  end

  describe 'validations' do
    let_it_be(:metadata) { create(:ml_model_metadata, name: 'some_metadata') }
    let_it_be(:model) { metadata.model }

    it 'is unique within the model' do
      expect do
        model.metadata.create!(name: 'some_metadata', value: 'blah')
      end.to raise_error.with_message(/Name 'some_metadata' already taken/)
    end

    it 'a model is required' do
      expect do
        described_class.create!(name: 'some_metadata', value: 'blah')
      end.to raise_error.with_message(/Model must exist/)
    end
  end

  describe '.bulk_create!' do
    let_it_be(:model) { create(:ml_models) }

    def build_records(*names)
      names.map { |name| described_class.new(model: model, project_id: model.project_id, name: name, value: 'v') }
    end

    it 'raises an error when a name is already taken by an existing record' do
      create(:ml_model_metadata, model: model, name: 'tag1')

      expect { described_class.bulk_create!(build_records('tag2', 'tag1'), existing: model.metadata) }
        .to raise_error(ActiveRecord::RecordInvalid, "Validation failed: Name 'tag1' already taken")
        .and not_change { model.metadata.count }
    end

    it 'persists every attribute of the records' do
      described_class.bulk_create!(build_records('tag1'), existing: model.metadata)

      record = model.metadata.find_by(name: 'tag1')
      expect(record).to have_attributes(value: 'v', project_id: model.project_id)
      expect(record.created_at).to be_present
      expect(record.updated_at).to be_present
    end
  end
end
