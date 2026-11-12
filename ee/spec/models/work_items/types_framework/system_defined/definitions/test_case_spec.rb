# frozen_string_literal: true

require 'spec_helper'

RSpec.describe WorkItems::TypesFramework::SystemDefined::Definitions::TestCase, feature_category: :quality_management do
  describe '.widgets' do
    it 'returns the correct list of widgets' do
      expected_widgets = %w[
        award_emoji
        current_user_todos
        description
        labels
        linked_items
        notes
        notifications
        participants
        time_tracking
      ]

      expect(described_class.widgets).to match_array(expected_widgets)
    end
  end

  describe '.widget_options' do
    it 'returns an empty hash' do
      expect(described_class.widget_options).to eq({})
    end
  end

  describe '.configuration' do
    it 'returns the correct configuration hash' do
      expected_configuration = {
        id: 3,
        name: 'Test Case',
        base_type: 'test_case',
        icon_name: "work-item-test-case"
      }

      expect(described_class.configuration).to eq(expected_configuration)
    end
  end

  describe '.license_name' do
    it 'returns :quality_management' do
      expect(described_class.license_name).to eq(:quality_management)
    end
  end

  describe 'boolean flags' do
    it 'returns the correct values', :aggregate_failures do
      expect(described_class.use_legacy_view?).to be(true)
      expect(described_class.creatable?).to be(false)
      expect(described_class.can_be_conversion_target?).to be(false)
      expect(described_class.filterable_list_view?).to be(false)
      expect(described_class.disabled_workflow_type?).to be(true)
      expect(described_class.configurable?).to be(false)
      expect(described_class.supports_conversion?).to be(false)
      expect(described_class.supports_move_action?).to be(true)
    end
  end
end
