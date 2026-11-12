# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'Settings enforcement policies', feature_category: :security_policy_management do
  include Govern::FakeGlazEngineHelpers

  let_it_be(:group) { create(:group) }
  let_it_be(:organization) { group.organization }
  let_it_be(:user) { create(:user, owner_of: group) }

  let(:block_message) { 'Keep "Pipelines must succeed" enabled. Required by compliance.' }

  let(:pipeline_succeeds_rule) do
    [{ 'type' => 'setting_validation', 'rego' => 'package governance',
       'value' => { 'setting' => 'only_allow_merge_if_pipeline_succeeds', 'value' => true } }]
  end

  let!(:engine) { stub_govern_glaz_engine }
  let(:block_action) { [{ 'type' => 'block', 'value' => { 'message' => block_message } }] }

  before do
    stub_application_setting(policy_store_experiment_enabled: true)
    stub_licensed_features(security_orchestration_policies: true)
    stub_feature_flags(security_policies_v2: true)
    ::Organizations::OrganizationSetting.for(organization.id).update!(policy_store_experiment_enabled: true)

    # The gate's policy lookup and recording queries put the settings update just over the default budget.
    allow(Gitlab::QueryLimiting::Transaction).to receive(:threshold).and_return(120)
  end

  def create_policy(trigger_type:, mode:, name:, actions:)
    policy = create(:govern_policy, :without_namespace, organization: organization,
      trigger_type: trigger_type, mode: mode, name: name,
      rules: pipeline_succeeds_rule, actions: actions)
    engine.policies << policy
  end

  def put_pipeline_succeeds(project, value)
    put project_settings_merge_requests_path(project),
      params: { project: { only_allow_merge_if_pipeline_succeeds: value } }
  end

  describe 'policy 2: ensure-pipeline-success-on-change (Project Settings Change trigger)' do
    let_it_be_with_reload(:project) do
      create(:project, group: group, only_allow_merge_if_pipeline_succeeds: true)
    end

    before do
      sign_in(user)
    end

    context 'in warn mode' do
      before do
        create_policy(trigger_type: 'project.before_settings_update', mode: :warn,
          name: 'ensure-pipeline-success-on-change', actions: block_action)
      end

      it 'lets the violating change through and shows the authored message as a warning flash', :aggregate_failures do
        put_pipeline_succeeds(project, '0')

        expect(response).to redirect_to(project_settings_merge_requests_path(project))
        expect(flash[:notice]).to include('successfully updated')
        expect(flash[:warning]).to eq(block_message)
        expect(project.reload.only_allow_merge_if_pipeline_succeeds).to be(false)
      end

      it 'does not warn on a compliant change', :aggregate_failures do
        project.update!(only_allow_merge_if_pipeline_succeeds: false)

        put_pipeline_succeeds(project, '1')

        expect(response).to redirect_to(project_settings_merge_requests_path(project))
        expect(flash[:warning]).to be_nil
        expect(project.reload.only_allow_merge_if_pipeline_succeeds).to be(true)
      end
    end

    context 'in enforce mode' do
      before do
        create_policy(trigger_type: 'project.before_settings_update', mode: :enforce,
          name: 'ensure-pipeline-success-on-change', actions: block_action)
      end

      it 'refuses the violating change with the authored message and keeps the stored value', :aggregate_failures do
        put_pipeline_succeeds(project, '0')

        expect(response).to have_gitlab_http_status(:ok)
        expect(flash[:alert]).to eq(block_message)
        expect(project.reload.only_allow_merge_if_pipeline_succeeds).to be(true)
      end

      it 'lets a save through that re-posts a drifted setting unchanged', :aggregate_failures do
        project.update!(only_allow_merge_if_pipeline_succeeds: false)

        put_pipeline_succeeds(project, '0')

        expect(response).to redirect_to(project_settings_merge_requests_path(project))
        expect(flash[:alert]).to be_nil
      end

      it 'lets a compliant save through untouched', :aggregate_failures do
        put_pipeline_succeeds(project, '1')

        expect(response).to redirect_to(project_settings_merge_requests_path(project))
        expect(flash[:alert]).to be_nil
        expect(project.reload.only_allow_merge_if_pipeline_succeeds).to be(true)
      end
    end
  end

  describe 'a governed setting sent as a top-level REST API param', :api do
    let_it_be_with_reload(:project) { create(:project, group: group) }

    let(:pipeline_succeeds_rule) do
      [{ 'type' => 'setting_validation', 'rego' => 'package governance',
         'value' => { 'setting' => 'squash_option', 'value' => 'default_off' } }]
    end

    before do
      create_policy(trigger_type: 'project.before_settings_update', mode: :enforce,
        name: 'keep-squash-default-off', actions: block_action)
    end

    it 'refuses the violating change and reports it as a model error', :aggregate_failures do
      put api("/projects/#{project.id}", user), params: { squash_option: 'always' }

      expect(response).to have_gitlab_http_status(:bad_request)
      expect(json_response.dig('message', 'base')).to contain_exactly(block_message)
      expect(project.reload.squash_option).to eq('default_off')
    end
  end
end
