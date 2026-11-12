# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Namespaces::CascadeDuoSettingsWorker, feature_category: :ai_abstraction_layer do
  let(:group) { create(:group) }
  let(:user) { create(:user) }
  let(:setting_attributes) { { "duo_features_enabled" => true } }
  let(:always_on_attributes) { { "duo_features_enabled" => true, "lock_duo_features_enabled" => true } }

  subject(:worker) { described_class.new }

  it 'has a concurrency limit' do
    expect(described_class.get_concurrency_limit).to eq(10)
  end

  it 'is at version 1' do
    expect(described_class.version).to eq(1)
  end

  describe '.idempotency_arguments' do
    it 'keeps the arguments of jobs that carry setting values' do
      arguments = [group.id, setting_attributes, user.id]

      expect(described_class.idempotency_arguments(arguments)).to eq(arguments)
    end

    it 'ignores the order of setting names' do
      first = described_class.idempotency_arguments(
        [group.id, %w[duo_remote_flows_enabled duo_features_enabled], user.id, {}]
      )
      second = described_class.idempotency_arguments(
        [group.id, %w[duo_features_enabled duo_remote_flows_enabled], user.id, {}]
      )

      expect(first).to eq(second)
    end

    it 'keeps the user in the key' do
      first = described_class.idempotency_arguments([group.id, %w[duo_features_enabled], user.id, {}])
      second = described_class.idempotency_arguments([group.id, %w[duo_features_enabled], create(:user).id, {}])

      expect(first).not_to eq(second)
    end

    it 'keeps the flow selection in the key' do
      without_flows = described_class.idempotency_arguments([group.id, %w[duo_features_enabled], user.id, {}])
      with_flows = described_class.idempotency_arguments(
        [group.id, %w[duo_features_enabled], user.id, { 'enabled_foundational_flows' => ['code_review/v1'] }]
      )

      expect(without_flows).not_to eq(with_flows)
    end
  end

  describe '#perform' do
    it 'calls cascade_for_group on service with the correct arguments' do
      expect_next_instance_of(Ai::CascadeDuoSettingsService, setting_attributes, current_user: user) do |service|
        expect(service).to receive(:cascade_for_group).with(group)
      end

      worker.perform(group.id, setting_attributes, user.id)
    end

    context 'when user_id is not provided' do
      it 'calls cascade_for_group with nil current_user' do
        expect_next_instance_of(Ai::CascadeDuoSettingsService, setting_attributes, current_user: nil) do |service|
          expect(service).to receive(:cascade_for_group).with(group)
        end

        worker.perform(group.id, setting_attributes)
      end
    end

    context 'when user_id does not exist' do
      it 'calls cascade_for_group with nil current_user' do
        expect_next_instance_of(Ai::CascadeDuoSettingsService, setting_attributes, current_user: nil) do |service|
          expect(service).to receive(:cascade_for_group).with(group)
        end

        worker.perform(group.id, setting_attributes, non_existing_record_id)
      end
    end

    context 'when group does not exist' do
      it 'does not cascade' do
        expect(Ai::CascadeDuoSettingsService).not_to receive(:new)

        worker.perform(non_existing_record_id, setting_attributes, user.id)
      end
    end

    context 'when attributes originate from duo_availability = always_on' do
      it 'calls cascade_for_group with the always_on attribute combination' do
        expect_next_instance_of(Ai::CascadeDuoSettingsService, always_on_attributes, current_user: user) do |service|
          expect(service).to receive(:cascade_for_group).with(group)
        end

        worker.perform(group.id, always_on_attributes, user.id)
      end
    end

    context 'when the job carries setting names' do
      before do
        group.namespace_settings.update!(duo_features_enabled: false, duo_remote_flows_enabled: true)
      end

      it 'cascades the values the group has when the job runs' do
        expect_next_instance_of(
          Ai::CascadeDuoSettingsService,
          { 'duo_features_enabled' => false, 'duo_remote_flows_enabled' => true },
          current_user: user
        ) do |service|
          expect(service).to receive(:cascade_for_group).with(group)
        end

        worker.perform(group.id, %w[duo_features_enabled duo_remote_flows_enabled], user.id, {})
      end

      it 'passes the flow selection from the options' do
        expect_next_instance_of(
          Ai::CascadeDuoSettingsService,
          { 'duo_features_enabled' => false, 'enabled_foundational_flows' => ['code_review/v1'] },
          current_user: user
        ) do |service|
          expect(service).to receive(:cascade_for_group).with(group)
        end

        worker.perform(
          group.id, %w[duo_features_enabled], user.id, { 'enabled_foundational_flows' => ['code_review/v1'] }
        )
      end

      context 'when group does not exist' do
        it 'does not cascade the flow selection' do
          expect(Ai::CascadeDuoSettingsService).not_to receive(:new)

          worker.perform(
            non_existing_record_id, [], user.id, { 'enabled_foundational_flows' => ['code_review/v1'] }
          )
        end
      end
    end

    context 'when the cascade runs through Ai::CascadeDuoSettingsService' do
      let(:subgroup) { create(:group, parent: group) }

      def subgroup_duo_features_enabled
        NamespaceSetting.where(namespace_id: subgroup.id).pick(:duo_features_enabled)
      end

      before do
        group.namespace_settings.update!(duo_features_enabled: false)
        NamespaceSetting.where(namespace_id: subgroup.id).update_all(duo_features_enabled: nil)
      end

      it 'cascades the values carried by a job queued with setting values' do
        worker.perform(group.id, { 'duo_features_enabled' => true }, user.id)

        expect(subgroup_duo_features_enabled).to be(true)
      end

      it "cascades the group's current values for a job queued with setting names" do
        worker.perform(group.id, %w[duo_features_enabled], user.id, {})

        expect(subgroup_duo_features_enabled).to be(false)
      end
    end
  end
end
