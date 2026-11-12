# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Ai::DuoWorkflows::GovernanceCeiling, feature_category: :duo_agent_platform do
  using RSpec::Parameterized::TableSyntax

  let_it_be(:root_group) { create(:group) }
  let_it_be(:subgroup) { create(:group, parent: root_group) }
  let_it_be(:sibling_subgroup) { create(:group, parent: root_group) }
  let_it_be(:project) { create(:project, group: subgroup) }
  let_it_be(:user_project) { create(:project, :in_user_namespace) }

  describe '.enabled?' do
    subject(:enabled) { described_class.enabled?(container) }

    context 'when the flag is enabled for the root group' do
      before do
        stub_feature_flags(duo_workflow_governance_ceiling: root_group)
      end

      where(:container) { [ref(:root_group), ref(:subgroup), ref(:project)] }

      with_them do
        it { is_expected.to be(true) }
      end
    end

    context 'when the flag is enabled for a subgroup only' do
      before do
        stub_feature_flags(duo_workflow_governance_ceiling: subgroup)
      end

      where(:container, :result) do
        ref(:project)          | true
        ref(:subgroup)         | true
        ref(:root_group)       | false
        ref(:sibling_subgroup) | false
      end

      with_them do
        it { is_expected.to be(result) }
      end
    end

    context 'when the flag is enabled for an unrelated group' do
      before do
        stub_feature_flags(duo_workflow_governance_ceiling: create(:group))
      end

      let(:container) { project }

      it { is_expected.to be(false) }
    end

    context 'when the project is in a user namespace' do
      let(:container) { user_project }

      it 'checks the user namespace' do
        stub_feature_flags(duo_workflow_governance_ceiling: user_project.namespace)

        is_expected.to be(true)
      end

      it 'is false when the flag is enabled elsewhere' do
        stub_feature_flags(duo_workflow_governance_ceiling: root_group)

        is_expected.to be(false)
      end
    end

    context 'when there is no container' do
      let(:container) { nil }

      it { is_expected.to be(false) }
    end
  end
end
