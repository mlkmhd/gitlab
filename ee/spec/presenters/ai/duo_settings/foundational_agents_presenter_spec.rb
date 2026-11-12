# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Ai::DuoSettings::FoundationalAgentsPresenter, feature_category: :duo_agent_platform do
  include_context 'with mocked Foundational Chat Agents'

  subject(:presenter) { described_class.new(group, current_user: user) }

  let(:references) { presenter.listed_statuses.pluck(:reference) }
  let(:user) { build_stubbed(:user) }
  let(:group) { build_stubbed(:group) }
  let(:orbit_enabled) { true }
  let(:ultimate) { true }

  let(:mocked_foundational_chat_agents) do
    [
      foundational_duo_chat_agent,
      foundational_chat_agent_1,
      { id: 3, reference: 'security_analyst_agent', version: 'v1', name: 'Security Analyst',
        description: 'Security agent', ultimate_only: true },
      { id: 4, reference: 'orbit_agent', version: 'v1', name: 'Orbit', description: 'Orbit agent' }
    ]
  end

  before do
    allow(::Analytics::KnowledgeGraph).to receive(:enabled_for?).with(user).and_return(orbit_enabled)
    allow(group).to receive(:licensed_feature_available?).with(:ai_features).and_return(ultimate)
  end

  it 'lists every agent but Duo Chat' do
    expect(references).to contain_exactly(foundational_chat_agent_1_ref, 'security_analyst_agent', 'orbit_agent')
  end

  context 'when Orbit is off for the user' do
    let(:orbit_enabled) { false }

    it 'hides the Orbit agent' do
      expect(references).to contain_exactly(foundational_chat_agent_1_ref, 'security_analyst_agent')
    end
  end

  context 'without the Ultimate license' do
    let(:ultimate) { false }

    it 'hides the Ultimate-only agents' do
      expect(references).to contain_exactly(foundational_chat_agent_1_ref, 'orbit_agent')
    end
  end

  describe '#readiness_card_enabled?' do
    it 'follows the flag for the top-level group' do
      stub_feature_flags(duo_group_agent_readiness_settings: false)

      expect(presenter.readiness_card_enabled?).to be(false)

      stub_feature_flags(duo_group_agent_readiness_settings: group)

      expect(presenter.readiness_card_enabled?).to be(true)
    end
  end

  describe '#selected_statuses' do
    subject(:selected_references) { presenter.selected_statuses.pluck(:reference) }

    let(:mocked_foundational_chat_agents) do
      super() << { id: 5, reference: 'onboarding_guide', version: 'v1', name: 'Onboarding agent',
        description: 'Onboarding agent' }
    end

    let(:enabled_references) { ['chat', foundational_chat_agent_1_ref, 'orbit_agent', 'onboarding_guide'] }

    before do
      stub_feature_flags(onboarding_guide_agent: group)
      allow(group).to receive(:enabled_foundational_agents).and_return(
        ::Ai::FoundationalChatAgent.all.select { |agent| enabled_references.include?(agent.reference) }
      )
    end

    it 'keeps the listed agents that are on' do
      expect(selected_references).to contain_exactly(foundational_chat_agent_1_ref, 'orbit_agent', 'onboarding_guide')
    end

    context 'when the onboarding guide agent is still behind its flag for the group' do
      before do
        stub_feature_flags(onboarding_guide_agent: false)
      end

      it 'leaves it out, as Chat does' do
        expect(selected_references).to contain_exactly(foundational_chat_agent_1_ref, 'orbit_agent')
      end
    end

    context 'when Orbit is off for the user' do
      let(:orbit_enabled) { false }

      it 'leaves out the agents the settings page hides' do
        expect(selected_references).to contain_exactly(foundational_chat_agent_1_ref, 'onboarding_guide')
      end
    end

    context 'when no agent is on' do
      let(:enabled_references) { ['chat'] }

      it { is_expected.to be_empty }
    end
  end

  context 'with a stored status record and the Agents switch off' do
    let(:ai_settings) do
      build_stubbed(:namespace_ai_settings, namespace: group, foundational_agents_default_enabled: false)
    end

    let(:status_record) do
      build_stubbed(
        :namespace_foundational_agent_statuses,
        namespace: group,
        reference: foundational_chat_agent_1_ref,
        enabled: true
      )
    end

    before do
      stub_feature_flags(duo_group_agent_readiness_settings: group)
      allow(group).to receive_messages(ai_settings: ai_settings, foundational_agents_status_records: [status_record])
    end

    it 'lists the agents but selects none, not even one turned on by itself' do
      expect(presenter.listed_statuses.pluck(:reference)).to include(foundational_chat_agent_1_ref)
      expect(presenter.selected_statuses).to be_empty
    end
  end

  context 'for a subgroup' do
    let(:root_group) { build_stubbed(:group) }
    let(:group) { build_stubbed(:group, parent: root_group) }
    let(:root_statuses) { [{ reference: foundational_chat_agent_1_ref, name: 'Agent 1', enabled: false }] }

    before do
      allow(group).to receive(:root_ancestor).and_return(root_group)
      allow(root_group).to receive(:foundational_agents_statuses).and_return(root_statuses)
    end

    it 'lists the statuses of the top-level group' do
      expect(presenter.listed_statuses).to eq(root_statuses)
    end
  end
end
