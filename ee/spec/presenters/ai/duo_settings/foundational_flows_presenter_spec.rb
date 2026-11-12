# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Ai::DuoSettings::FoundationalFlowsPresenter, :aggregate_failures, :saas_gitlab_com_subscriptions, feature_category: :duo_agent_platform do
  subject(:presenter) { described_class.new(group) }

  let(:listed_references) { presenter.listed_flows.map(&:foundational_flow_reference) }

  # rubocop:disable RSpec/FactoryBot/AvoidCreate -- the presenter reads persisted flow selections
  let_it_be(:root_group) { create(:group) }
  let_it_be(:subgroup) { create(:group, parent: root_group) }
  let_it_be(:flow) { create(:ai_catalog_item, :with_foundational_flow_reference, :public) }
  let_it_be(:beta_flow) do
    create(:ai_catalog_item, :with_foundational_flow_reference, :public,
      foundational_flow_reference: 'recommend_reviewers/v1')
  end

  before_all do
    create(:ai_catalog_enabled_foundational_flow, :for_namespace, namespace: root_group, catalog_item: flow)
    create(:ai_catalog_enabled_foundational_flow, :for_namespace, namespace: root_group, catalog_item: beta_flow)
  end
  # rubocop:enable RSpec/FactoryBot/AvoidCreate

  context 'for a top-level group' do
    let(:group) { root_group }

    it 'lists every available flow and its own selection' do
      expect(presenter.readiness_card_enabled?).to be(true)
      expect(listed_references).to include('code_review/v1', flow.foundational_flow_reference)
      expect(presenter.selected_flow_references).to eq([flow.foundational_flow_reference])
      expect(presenter.selected_flows.map(&:foundational_flow_reference)).to eq([flow.foundational_flow_reference])
    end

    it 'leaves a stored beta flow out of the selection while beta flows are off' do
      expect(root_group.selected_foundational_flow_references).to include('recommend_reviewers/v1')
      expect(listed_references).not_to include('recommend_reviewers/v1')
      expect(presenter.selected_flow_references).not_to include('recommend_reviewers/v1')
    end

    context 'when the group turned on beta flows' do
      before do
        allow(root_group).to receive(:duo_beta_flows_enabled?).and_return(true)
      end

      it 'lists and selects the stored beta flow again' do
        expect(listed_references).to include('recommend_reviewers/v1')
        expect(presenter.selected_flow_references)
          .to contain_exactly(flow.foundational_flow_reference, 'recommend_reviewers/v1')
      end
    end

    it 'leaves out a flow that needs no enablement' do
      expect(listed_references).not_to include('slack_assistant/v1')
    end

    context 'when slack_duo_group is off' do
      before do
        stub_feature_flags(slack_duo_group: false)
      end

      it 'lists a flow that needs no enablement' do
        expect(listed_references).to include('slack_assistant/v1')
      end
    end

    context 'when the readiness card is off' do
      before do
        stub_feature_flags(duo_group_agent_readiness_settings: false)
      end

      it 'still lists its own flows and keeps its stored selection as it is' do
        expect(presenter.readiness_card_enabled?).to be(false)
        expect(listed_references).to include('code_review/v1')
        expect(presenter.selected_flow_references)
          .to contain_exactly(flow.foundational_flow_reference, 'recommend_reviewers/v1')
      end
    end

    context 'when the per-instance lookup fails on GitLab Dedicated' do
      before do
        stub_saas_features(gitlab_com_subscriptions: false)
        stub_application_setting(gitlab_dedicated_instance: true, instance_level_ai_beta_features_enabled: true)
        allow(::Ai::Catalog::FoundationalFlow.fix_pipeline_v1).to receive(:available_on)
          .and_return(%i[gitlab_com dedicated_enabled_instances])
        allow(::Ai::Catalog::FoundationalFlows::EnabledFlowsClient).to receive(:enabled?).and_return(false)
      end

      it 'keeps the selected flow, which the card cannot list' do
        expect(listed_references).not_to include(flow.foundational_flow_reference)
        expect(presenter.selected_flow_references).to include(flow.foundational_flow_reference)
      end
    end
  end

  context 'for a subgroup' do
    let(:group) { subgroup }

    before do
      stub_feature_flags(duo_group_agent_readiness_settings: root_group)
    end

    it 'lists only the flows the top-level group picked, with no selection of its own' do
      expect(presenter.readiness_card_enabled?).to be(true)
      expect(listed_references).to eq([flow.foundational_flow_reference])
      expect(presenter.selected_flows).to eq(presenter.listed_flows)
      expect(presenter.selected_flow_references).to eq([])
    end

    context 'when the readiness card is on only for the subgroup' do
      before do
        stub_feature_flags(duo_group_agent_readiness_settings: subgroup)
      end

      it 'lists no flows, as without the card' do
        expect(presenter.readiness_card_enabled?).to be(false)
        expect(presenter.listed_flows).to eq([])
        expect(presenter.selected_flow_references).to eq([])
      end
    end

    context 'when only the top-level group turned on experiment features' do
      let(:group) { beta_subgroup }

      # rubocop:disable RSpec/FactoryBot/AvoidCreate -- the beta flows read the persisted setting
      let_it_be(:beta_root_group) do
        create(:group, namespace_settings: build(:namespace_settings, experiment_features_enabled: true))
      end

      let_it_be(:beta_subgroup) { create(:group, parent: beta_root_group) }

      before_all do
        create(:ai_catalog_enabled_foundational_flow, :for_namespace, namespace: beta_root_group,
          catalog_item: beta_flow)
      end
      # rubocop:enable RSpec/FactoryBot/AvoidCreate

      before do
        stub_feature_flags(duo_group_agent_readiness_settings: beta_root_group)
      end

      it 'lists the beta flows the top-level group picked' do
        expect(listed_references).to eq(['recommend_reviewers/v1'])
      end
    end
  end
end
