# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Ai::Governance::AgentGovernance, feature_category: :software_composition_analysis do
  describe '.enabled_for?' do
    let_it_be(:group) { create(:group) }
    let_it_be_with_reload(:project) { create(:project, group: group) }
    let_it_be_with_reload(:personal_project) do
      create(:project, namespace: create(:user, :with_namespace).namespace)
    end

    subject(:enabled) { described_class.enabled_for?(project) }

    it { is_expected.to be(false) }

    it 'reads the project setting' do
      project.project_setting.update!(ai_governance_enabled: true)

      expect(enabled).to be(true)
    end

    it 'reads the project setting for a personal namespace on self-managed' do
      personal_project.project_setting.update!(ai_governance_enabled: true)

      expect(described_class.enabled_for?(personal_project)).to be(true)
    end

    context 'on GitLab.com' do
      before do
        stub_saas_features(gitlab_com_subscriptions: true)
      end

      it 'reads the project setting' do
        project.project_setting.update!(ai_governance_enabled: true)

        expect(enabled).to be(true)
      end

      it 'is false for a project in a personal namespace' do
        personal_project.project_setting.update!(ai_governance_enabled: true)

        expect(described_class.enabled_for?(personal_project)).to be(false)
      end
    end
  end

  describe '.report_disabled_to?' do
    let_it_be_with_reload(:project) { create(:project, :public) }
    let_it_be(:developer) { create(:user, developer_of: project) }
    let_it_be(:guest) { create(:user, guest_of: project) }
    let_it_be(:non_member) { create(:user) }

    it 'reports it to developers when governance is off' do
      expect(described_class.report_disabled_to?(developer, project)).to be(true)
    end

    it 'does not report it to guests or non-members' do
      expect(described_class.report_disabled_to?(guest, project)).to be(false)
      expect(described_class.report_disabled_to?(non_member, project)).to be(false)
    end

    it 'reports it to admins in admin mode', :enable_admin_mode do
      expect(described_class.report_disabled_to?(create(:admin), project)).to be(true)
    end

    it 'does not report it to admins outside admin mode' do
      expect(described_class.report_disabled_to?(create(:admin), project)).to be(false)
    end

    it 'does not report it when governance is on' do
      project.project_setting.update!(ai_governance_enabled: true)

      expect(described_class.report_disabled_to?(developer, project)).to be(false)
    end

    it 'does not report it when the ai_governance_session_gate feature flag is disabled' do
      stub_feature_flags(ai_governance_session_gate: false)

      expect(described_class.report_disabled_to?(developer, project)).to be(false)
    end
  end
end
