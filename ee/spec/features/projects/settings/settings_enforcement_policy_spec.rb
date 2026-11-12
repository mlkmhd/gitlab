# frozen_string_literal: true

require 'spec_helper'

# A member on the merge requests settings page tries to disable "Pipelines
# must succeed" under a Project Settings Change policy, in warn mode and in
# enforce mode. The spec stubs only the engine's evaluation, and the form, the
# controller, the gate and the flash rendering are all real.
RSpec.describe 'Projects > Settings > Merge requests > Settings enforcement policies',
  feature_category: :security_policy_management do
  include Govern::SettingsGateHelpers

  let_it_be(:group) { create(:group) }
  let_it_be(:organization) { group.organization }
  let_it_be(:user) { create(:user, owner_of: group) }
  let_it_be_with_reload(:project) do
    create(:project, group: group, only_allow_merge_if_pipeline_succeeds: true)
  end

  let(:block_message) { 'Keep "Pipelines must succeed" enabled. Required by compliance.' }

  let(:policy) do
    build_stubbed(:govern_policy, :without_namespace, organization: organization, mode: mode,
      name: 'ensure-pipeline-success-on-change')
  end

  def stub_evaluation
    stub_settings_gate_evaluation(policy: policy, setting: 'only_allow_merge_if_pipeline_succeeds',
      expected: true, actual: false, message: block_message)
  end

  before do
    stub_application_setting(policy_store_experiment_enabled: true)
    stub_licensed_features(security_orchestration_policies: true)
    stub_feature_flags(security_policies_v2: true)
    ::Organizations::OrganizationSetting.for(organization.id).update!(policy_store_experiment_enabled: true)
    stub_evaluation

    sign_in(user)
    visit project_settings_merge_requests_path(project)
  end

  context 'when the policy runs in warn mode' do
    let(:mode) { :warn }

    it 'saves the violating change and shows the authored message as a warning' do
      page.within '.merge-request-settings-form' do
        uncheck 'Pipelines must succeed'
        click_button 'Save changes'
      end

      expect(page).to have_content("Project '#{project.name}' was successfully updated.")
      expect(page).to have_content(block_message)
      expect(page).to have_unchecked_field('Pipelines must succeed')
      expect(project.reload.only_allow_merge_if_pipeline_succeeds).to be(false)
    end
  end

  context 'when the policy runs in enforce mode' do
    let(:mode) { :enforce }

    it 'refuses the violating change, shows the authored message, and keeps the setting enabled' do
      page.within '.merge-request-settings-form' do
        uncheck 'Pipelines must succeed'
        click_button 'Save changes'
      end

      expect(page).to have_content(block_message)
      expect(page).not_to have_content('successfully updated')
      expect(page).to have_checked_field('Pipelines must succeed')
      expect(project.reload.only_allow_merge_if_pipeline_succeeds).to be(true)
    end

    it 'lets a save that keeps the setting enabled through' do
      page.within '.merge-request-settings-form' do
        click_button 'Save changes'
      end

      expect(page).to have_content("Project '#{project.name}' was successfully updated.")
      expect(page).not_to have_content(block_message)
      expect(project.reload.only_allow_merge_if_pipeline_succeeds).to be(true)
    end
  end
end
