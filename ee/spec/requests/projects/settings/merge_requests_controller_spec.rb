# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Projects::Settings::MergeRequestsController, feature_category: :code_review_workflow do
  let_it_be(:project) { create(:project) }
  let_it_be(:user) { create(:user, maintainer_of: project) }

  let(:decisions_available) { true }

  before do
    sign_in(user)

    allow(::Gitlab::Duo::CodeReview).to receive(:decisions_settings_available?).and_return(decisions_available)
  end

  describe 'PATCH #update' do
    subject(:update_settings) do
      patch project_settings_merge_requests_path(project), params: {
        project: { project_setting_attributes: { duo_code_review_decisions_enabled: false } }
      }
    end

    it 'persists the decisions setting' do
      update_settings

      expect(project.project_setting.reload.attributes).to include('duo_code_review_decisions_enabled' => false)
    end

    context 'when Duo code review decisions are not available' do
      let(:decisions_available) { false }

      it 'does not permit the decisions setting' do
        update_settings

        expect(project.project_setting.reload.attributes).to include('duo_code_review_decisions_enabled' => nil)
      end
    end
  end

  describe 'the settings change gate', feature_category: :security_policy_management do
    include Govern::SettingsGateHelpers

    let(:policy_mode) { :warn }
    let(:policy) do
      build_stubbed(:govern_policy, :without_namespace, organization: project.organization,
        trigger_type: 'project.before_settings_update', mode: policy_mode, name: 'Baseline',
        rules: [{ 'type' => 'setting_validation', 'rego' => 'package governance',
                  'value' => { 'setting' => 'only_allow_merge_if_pipeline_succeeds', 'value' => true } }],
        actions: [{ 'type' => 'block', 'value' => { 'message' => 'Compliance-sensitive control' } }])
    end

    before do
      stub_application_setting(policy_store_experiment_enabled: true)
      stub_licensed_features(security_orchestration_policies: true)
      stub_feature_flags(security_policies_v2: true)
      ::Organizations::OrganizationSetting.for(project.organization_id).update!(policy_store_experiment_enabled: true)
      Project.find(project.id).update!(only_allow_merge_if_pipeline_succeeds: true)
    end

    def stub_evaluation
      stub_settings_gate_evaluation(policy: policy, setting: 'only_allow_merge_if_pipeline_succeeds',
        expected: true, actual: false, message: 'Compliance-sensitive control')
    end

    describe 'PUT #update with a warn-mode settings policy' do
      it 'saves the change and shows the warn message as a warning flash', :aggregate_failures do
        stub_evaluation

        put project_settings_merge_requests_path(project),
          params: { project: { only_allow_merge_if_pipeline_succeeds: '0' } }

        expect(response).to redirect_to(project_settings_merge_requests_path(project))
        expect(flash[:notice]).to include('successfully updated')
        expect(flash[:warning]).to eq('Compliance-sensitive control')
      end
    end

    describe 'PUT #update with an enforce-mode settings policy' do
      let(:policy_mode) { :enforce }

      it 'refuses the change with the authored message and keeps the stored value', :aggregate_failures do
        stub_evaluation

        put project_settings_merge_requests_path(project),
          params: { project: { only_allow_merge_if_pipeline_succeeds: '0' } }

        expect(response).to have_gitlab_http_status(:ok)
        expect(flash[:alert]).to eq('Compliance-sensitive control')
        expect(project.reload.only_allow_merge_if_pipeline_succeeds).to be(true)
      end
    end
  end
end
