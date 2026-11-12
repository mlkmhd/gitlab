# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Analytics::DevopsAdoption::EnabledNamespace do
  using RSpec::Parameterized::TableSyntax

  describe 'associations' do
    subject { build(:devops_adoption_enabled_namespace) }

    it { is_expected.to have_many(:snapshots) }
    it { is_expected.to belong_to(:namespace) }
    it { is_expected.to belong_to(:display_namespace) }
  end

  describe 'validation' do
    subject { build(:devops_adoption_enabled_namespace) }

    it { is_expected.to validate_presence_of(:namespace) }
    it { is_expected.to validate_uniqueness_of(:namespace).scoped_to(:display_namespace_id) }

    describe 'organization boundary' do
      let_it_be(:organization) { create(:organization) }
      let_it_be(:other_organization) { create(:organization) }
      let_it_be(:isolated_organization) { create(:organization, :isolated) }
      let_it_be(:other_isolated_organization) { create(:organization, :isolated) }

      let(:error_message) { 'Namespace must be in the same organization as the display namespace' }

      where(:namespace_organization, :display_organization, :valid) do
        ref(:organization)          | ref(:organization)                | true
        ref(:isolated_organization) | ref(:isolated_organization)       | true
        ref(:organization)          | ref(:other_organization)          | true
        ref(:isolated_organization) | ref(:organization)                | false
        ref(:organization)          | ref(:isolated_organization)       | false
        ref(:isolated_organization) | ref(:other_isolated_organization) | false
      end

      with_them do
        it 'is valid unless the organizations differ and either one is isolated' do
          enabled_namespace = build(:devops_adoption_enabled_namespace,
            namespace: create(:group, organization: namespace_organization),
            display_namespace: create(:group, organization: display_organization))

          expect(enabled_namespace.valid?).to be(valid)
          expect(enabled_namespace.errors.full_messages).to eq(valid ? [] : [error_message])
        end
      end

      it 'is valid without a display namespace' do
        enabled_namespace = build(:devops_adoption_enabled_namespace,
          namespace: create(:group, organization: isolated_organization), display_namespace: nil)

        expect(enabled_namespace).to be_valid
      end
    end
  end

  describe '.ordered_by_name' do
    subject(:enabled_namespaces) { described_class.ordered_by_name }

    it 'orders enabled_namespaces by namespace name' do
      enabled_namespace_1 = create(:devops_adoption_enabled_namespace, namespace: create(:group, name: 'bbb'))
      enabled_namespace_2 = create(:devops_adoption_enabled_namespace, namespace: create(:group, name: 'aaa'))

      expect(enabled_namespaces).to eq([enabled_namespace_2, enabled_namespace_1])
    end
  end

  context 'with shared enabled namespaces' do
    let_it_be(:enabled_namespace1) { create(:devops_adoption_enabled_namespace) }
    let_it_be(:enabled_namespace2) { create(:devops_adoption_enabled_namespace) }
    let_it_be(:enabled_namespace3) { create(:devops_adoption_enabled_namespace) }

    describe '.for_namespaces' do
      subject(:enabled_namespaces) { described_class.for_namespaces(namespaces) }

      let_it_be(:namespaces) { [enabled_namespace1.namespace, enabled_namespace2.namespace] }

      it 'selects enabled_namespaces for given namespaces only' do
        expect(enabled_namespaces).to match_array([enabled_namespace1, enabled_namespace2])
      end
    end

    describe '.for_display_namespaces' do
      subject(:enabled_namespaces) { described_class.for_display_namespaces(namespaces) }

      let_it_be(:namespaces) { [enabled_namespace1.display_namespace, enabled_namespace2.display_namespace] }

      it 'selects enabled_namespaces for given namespaces only' do
        expect(enabled_namespaces).to match_array([enabled_namespace1, enabled_namespace2])
      end
    end
  end

  describe '.for_parent' do
    let_it_be(:group) { create :group }
    let_it_be(:subgroup) { create :group, parent: group }
    let_it_be(:group2) { create :group }

    let_it_be(:enabled_namespace1) { create(:devops_adoption_enabled_namespace, namespace: group) }
    let_it_be(:enabled_namespace2) { create(:devops_adoption_enabled_namespace, namespace: subgroup) }
    let_it_be(:enabled_namespace3) { create(:devops_adoption_enabled_namespace, namespace: group2) }

    subject(:enabled_namespaces) { described_class.for_parent(group) }

    it 'selects enabled_namespaces for given namespace only' do
      expect(enabled_namespaces).to match_array([enabled_namespace1, enabled_namespace2])
    end
  end

  describe '.latest_snapshot' do
    it 'loads the latest snapshot' do
      enabled_namespace = create(:devops_adoption_enabled_namespace)
      latest_snapshot = create(:devops_adoption_snapshot, namespace: enabled_namespace.namespace, end_time: 2.days.ago)
      create(:devops_adoption_snapshot, namespace: enabled_namespace.namespace, end_time: 5.days.ago)
      create(:devops_adoption_snapshot, end_time: 1.hour.ago)

      expect(enabled_namespace.latest_snapshot).to eq(latest_snapshot)
    end
  end

  describe '.pending_calculation' do
    let!(:enabled_namespace_without_snasphot) { create :devops_adoption_enabled_namespace }

    let!(:enabled_namespace_with_not_finalized) do
      create(:devops_adoption_enabled_namespace).tap do |enabled_namespace|
        create(:devops_adoption_snapshot, namespace: enabled_namespace.namespace, recorded_at: 1.year.ago)
      end
    end

    let!(:enabled_namespace_with_finalized) do
      create(:devops_adoption_enabled_namespace).tap do |enabled_namespace|
        create(:devops_adoption_snapshot, namespace: enabled_namespace.namespace)
      end
    end

    it 'returns all namespaces without finalized snapshot for previous month' do
      expect(described_class.pending_calculation).to match_array([enabled_namespace_without_snasphot, enabled_namespace_with_not_finalized])
    end
  end
end
