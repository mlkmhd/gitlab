# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Gitlab::BackgroundOperations::RedisStore, feature_category: :security_asset_inventories do
  let(:operation_type) { 'attribute_update' }
  let(:user_id) { 1 }
  let(:total_items) { 10 }
  let(:parameters) { { 'attribute_ids' => [1, 2], 'mode' => 'ADD' } }
  let(:created_operation_ids) { [] }
  let(:operation_id) { create_test_operation }

  after do
    created_operation_ids.each { |id| described_class.delete_operation(id) }
  end

  def create_test_operation(**args)
    defaults = {
      operation_type: operation_type,
      user_id: user_id,
      total_items: total_items,
      parameters: parameters
    }
    described_class.create_operation(**defaults.merge(args)).tap { |id| created_operation_ids << id }
  end

  describe '.create_operation' do
    it 'creates operation in Redis with all fields and returns operation_id' do
      op_id = create_test_operation

      expect(op_id).to match(/^attribute_update_1_\d+_[a-f0-9]+$/)

      operation = described_class.get_operation(op_id)

      expect(operation).to have_attributes(
        id: op_id,
        operation_type: operation_type,
        user_id: user_id,
        parameters: parameters,
        total_items: total_items,
        successful_items: 0,
        failed_items: 0
      )
    end

    it 'defaults parameters to empty hash' do
      op_id = create_test_operation(parameters: {})

      operation = described_class.get_operation(op_id)

      expect(operation.parameters).to eq({})
    end
  end

  describe '.increment_successful' do
    it 'increments successful items' do
      described_class.increment_successful(operation_id, 5)

      operation = described_class.get_operation(operation_id)
      expect(operation.successful_items).to eq(5)
    end

    it 'increments by 1 by default' do
      described_class.increment_successful(operation_id)

      operation = described_class.get_operation(operation_id)
      expect(operation.successful_items).to eq(1)
    end
  end

  describe '.add_failed_item' do
    it 'adds failed item and increments counter atomically' do
      described_class.add_failed_item(
        operation_id,
        entity_id: 10,
        entity_type: 'Project',
        entity_name: 'My Project',
        entity_full_path: 'my-group/my-project',
        error_message: 'Permission denied'
      )

      operation = described_class.get_operation(operation_id)
      expect(operation.failed_items).to eq(1)

      items = described_class.get_failed_items(operation_id)
      expect(items.size).to eq(1)
      expect(items.first).to include(
        'entity_id' => 10,
        'entity_type' => 'Project',
        'entity_name' => 'My Project',
        'entity_full_path' => 'my-group/my-project',
        'error_message' => 'Permission denied'
      )
    end

    it 'adds multiple failed items' do
      described_class.add_failed_item(
        operation_id,
        entity_id: 10,
        entity_type: 'Project',
        error_message: 'Error 1'
      )
      described_class.add_failed_item(
        operation_id,
        entity_id: 20,
        entity_type: 'Group',
        error_message: 'Error 2'
      )

      operation = described_class.get_operation(operation_id)
      expect(operation.failed_items).to eq(2)

      items = described_class.get_failed_items(operation_id)
      expect(items.size).to eq(2)
    end

    it 'keeps only the first MAX_FAILED_ITEMS entries while counting every failure' do
      stub_const("#{described_class}::MAX_FAILED_ITEMS", 3)

      5.times do |i|
        described_class.add_failed_item(
          operation_id,
          entity_id: i,
          entity_type: 'Project',
          error_message: "Error #{i}"
        )
      end

      operation = described_class.get_operation(operation_id)
      expect(operation.failed_items).to eq(5)

      items = described_class.get_failed_items(operation_id)
      expect(items.map { |item| item['entity_id'] }).to eq([0, 1, 2])
    end

    it 'truncates an error message that carries a whole failing statement' do
      stub_const("#{described_class}::MAX_ERROR_MESSAGE_LENGTH", 20)

      described_class.add_failed_item(
        operation_id,
        entity_id: 10,
        entity_type: 'Project',
        error_message: 'a' * 100
      )

      item = described_class.get_failed_items(operation_id).first

      expect(item['error_message'].size).to eq(20)
      expect(item['error_message']).to end_with('...')
    end

    it 'stores no error message when the failure carries none' do
      described_class.add_failed_item(
        operation_id,
        entity_id: 10,
        entity_type: 'Project',
        error_message: nil
      )

      item = described_class.get_failed_items(operation_id).first

      expect(item).not_to have_key('error_message')
      expect(item).not_to have_key('omitted_error_messages')
    end

    context 'when the error message is an array' do
      it 'stores every message when the array is within the cap' do
        described_class.add_failed_item(
          operation_id,
          entity_id: 10,
          entity_type: 'Group',
          error_message: ['Error 1', 'Error 2']
        )

        item = described_class.get_failed_items(operation_id).first

        expect(item['error_message']).to eq(['Error 1', 'Error 2'])
        expect(item).not_to have_key('omitted_error_messages')
      end

      it 'caps the messages and records how many were dropped' do
        stub_const("#{described_class}::MAX_ERROR_MESSAGES", 2)

        described_class.add_failed_item(
          operation_id,
          entity_id: 10,
          entity_type: 'Group',
          error_message: ['Error 1', 'Error 2', 'Error 3', 'Error 4']
        )

        item = described_class.get_failed_items(operation_id).first

        expect(item['error_message']).to eq(['Error 1', 'Error 2'])
        expect(item['omitted_error_messages']).to eq(2)
      end

      it 'truncates each message it keeps' do
        stub_const("#{described_class}::MAX_ERROR_MESSAGE_LENGTH", 20)

        described_class.add_failed_item(
          operation_id,
          entity_id: 10,
          entity_type: 'Group',
          error_message: ['a' * 100, 'short']
        )

        item = described_class.get_failed_items(operation_id).first

        expect(item['error_message']).to eq(["#{'a' * 17}...", 'short'])
      end
    end

    it 'allows duplicate failures for the same entity_id with different types' do
      described_class.add_failed_item(
        operation_id,
        entity_id: 10,
        entity_type: 'Project',
        error_message: 'First error'
      )
      described_class.add_failed_item(
        operation_id,
        entity_id: 10,
        entity_type: 'Group',
        error_message: 'Second error'
      )

      operation = described_class.get_operation(operation_id)
      expect(operation.failed_items).to eq(2)

      items = described_class.get_failed_items(operation_id)
      expect(items.size).to eq(2)
    end
  end

  describe '.get_operation' do
    it 'returns nil if operation does not exist' do
      operation = described_class.get_operation('nonexistent')

      expect(operation).to be_nil
    end

    it 'returns nil when a counter increment re-created the hash after finalization' do
      described_class.claim_for_finalization(operation_id)
      described_class.increment_successful(operation_id)

      expect(described_class.get_operation(operation_id)).to be_nil
    end

    it 'returns operation as struct' do
      operation = described_class.get_operation(operation_id)

      expect(operation).to be_a(described_class::Operation)
      expect(operation.id).to eq(operation_id)
      expect(operation.parameters).to eq(parameters)
    end
  end

  describe '.get_failed_items' do
    it 'returns empty array if no failed items' do
      items = described_class.get_failed_items(operation_id)

      expect(items).to eq([])
    end

    it 'returns all failed items' do
      3.times do |i|
        described_class.add_failed_item(
          operation_id,
          entity_id: i,
          entity_type: 'Project',
          error_message: "Error #{i}"
        )
      end

      items = described_class.get_failed_items(operation_id)

      expect(items.size).to eq(3)
    end
  end

  describe '.claim_for_finalization' do
    it 'succeeds for the first caller only' do
      expect(described_class.claim_for_finalization(operation_id)).to eq([])
      expect(described_class.claim_for_finalization(operation_id)).to be_nil
    end

    it 'returns nil for an operation that does not exist' do
      expect(described_class.claim_for_finalization('nonexistent')).to be_nil
    end

    it 'cannot be claimed again after a counter increment re-created the hash' do
      expect(described_class.claim_for_finalization(operation_id)).to eq([])
      described_class.increment_successful(operation_id)

      expect(described_class.claim_for_finalization(operation_id)).to be_nil
    end

    it 'hands the failed items to the winner and leaves nothing behind', :aggregate_failures do
      described_class.add_failed_item(
        operation_id,
        entity_id: 10,
        entity_type: 'Project',
        error_message: 'Error'
      )

      claimed = described_class.claim_for_finalization(operation_id)

      expect(claimed.map { |item| item['entity_id'] }).to eq([10])
      expect(described_class.get_operation(operation_id)).to be_nil
      expect(described_class.get_failed_items(operation_id)).to eq([])
    end
  end

  describe '.delete_operation' do
    it 'deletes operation and failed items' do
      described_class.add_failed_item(
        operation_id,
        entity_id: 10,
        entity_type: 'Project',
        error_message: 'Error'
      )

      described_class.delete_operation(operation_id)

      operation = described_class.get_operation(operation_id)
      items = described_class.get_failed_items(operation_id)

      expect(operation).to be_nil
      expect(items).to eq([])
    end
  end
end
