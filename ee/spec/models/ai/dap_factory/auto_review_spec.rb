# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Ai::DapFactory::AutoReview, feature_category: :dap_triggers do
  let_it_be_with_reload(:project) { create(:project, :in_group) }

  let(:available) { true }
  let(:decisions_available) { true }

  subject(:auto_review) { described_class.new(project) }

  before do
    project.project_setting.update!(auto_duo_code_review_enabled: false, duo_code_review_decisions_enabled: false)
    allow(::Gitlab::Duo::CodeReview).to receive(:available?).with(project).and_return(available)
    allow(::Gitlab::Duo::CodeReview).to receive(:decisions_settings_available?)
      .with(project).and_return(decisions_available)
  end

  it 'reports that automatic reviews are available but off' do
    expect(auto_review).to have_attributes(available?: true, enabled?: false, decisions_enabled?: false, locked?: false)
  end

  context 'when automatic reviews and decisions are on' do
    before do
      project.project_setting.update!(auto_duo_code_review_enabled: true, duo_code_review_decisions_enabled: true)
    end

    it { is_expected.to have_attributes(enabled?: true, decisions_enabled?: true) }

    context 'when decisions settings are not available' do
      let(:decisions_available) { false }

      it { is_expected.to have_attributes(decisions_enabled?: false) }
    end
  end

  context 'when Duo Code Review is not available' do
    let(:available) { false }

    before do
      project.project_setting.update!(auto_duo_code_review_enabled: true)
    end

    it { is_expected.to have_attributes(available?: false, enabled?: false) }
  end

  context 'when the instance locks automatic reviews' do
    before do
      stub_application_setting(lock_auto_duo_code_review_enabled: true)
    end

    it { is_expected.to have_attributes(locked?: true) }
  end
end
