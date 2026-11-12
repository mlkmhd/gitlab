# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Ai::ToolRules::AutoModePromotion, feature_category: :duo_agent_platform do
  let_it_be(:group) { create(:group) }
  let_it_be(:project) { create(:project, group: group) }

  let(:surface) { :ide }
  let(:container) { project }
  let(:requested_project) { nil }
  let(:policy) do
    { default_ask_tools: %w[run_command], ask_tools: %w[edit_file], denied_tools: %w[mkdir] }
  end

  subject(:promote_list) { described_class.promote_list(policy:, surface:, container:, requested_project:) }

  before do
    allow(::Ai::DuoSettings::AutoMode).to receive(:consented?).with(container: project).and_return(true)
  end

  it 'lists the default asks' do
    expect(promote_list).to eq(%w[run_command])
  end

  where(surface: [
    nil, :web, :chat, :chat_partial, ::Ai::ToolRules::GovernanceSurface::LOCAL,
    ::Ai::ToolRules::GovernanceSurface::BACKGROUND, ::Ai::ToolRules::GovernanceSurface::UNGOVERNED
  ])

  with_them do
    it { is_expected.to be_nil }
  end

  context 'without a container' do
    let(:container) { nil }

    it { is_expected.to be_nil }
  end

  context 'when duo_auto_mode_promotion is disabled for the root group' do
    before do
      stub_feature_flags(duo_auto_mode_promotion: create(:group))
    end

    it { is_expected.to be_nil }
  end

  context 'without consent' do
    before do
      allow(::Ai::DuoSettings::AutoMode).to receive(:consented?).with(container: project).and_return(false)
    end

    it { is_expected.to be_nil }
  end

  context 'with a requested project' do
    let(:requested_project) { build_stubbed(:project, group: group) }

    it 'is nil without its consent' do
      allow(::Ai::DuoSettings::AutoMode).to receive(:consented?).with(container: requested_project).and_return(false)

      expect(promote_list).to be_nil
    end
  end
end
