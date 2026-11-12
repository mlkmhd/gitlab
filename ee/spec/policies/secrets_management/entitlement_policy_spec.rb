# frozen_string_literal: true

require 'spec_helper'

RSpec.describe SecretsManagement::EntitlementPolicy, feature_category: :secrets_management do
  let(:user) { build(:user) }
  let(:root_group) { build(:group) }
  let(:subgroup) { build(:group, parent: root_group) }
  let(:entitlement) { SecretsManagement::Entitlement.new(state: :trial) }
  let(:adapter) do
    Types::SecretsManagement::EntitlementType::Adapter.new(
      entitlement: entitlement, group: group, queried_group: queried_group
    )
  end

  subject(:policy) { described_class.new(user, adapter) }

  def delegated_subjects
    policy.delegated_policies.values.map(&:subject)
  end

  context 'when queried through a subgroup' do
    let(:group) { root_group }
    let(:queried_group) { subgroup }

    it 'delegates to the policy of the subgroup', :aggregate_failures do
      is_expected.to delegate_to(GroupPolicy)
      expect(delegated_subjects).to contain_exactly(subgroup)
    end
  end

  context 'with a top-level group entitlement and no queried group' do
    let(:group) { root_group }
    let(:queried_group) { nil }

    it 'delegates to the policy of the top-level group', :aggregate_failures do
      is_expected.to delegate_to(GroupPolicy)
      expect(delegated_subjects).to contain_exactly(root_group)
    end
  end

  context 'with the instance-wide entitlement' do
    let(:group) { nil }
    let(:queried_group) { nil }

    it { is_expected.to delegate_to(GlobalPolicy) }
  end
end
