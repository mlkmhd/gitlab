# frozen_string_literal: true

require 'spec_helper'

RSpec.describe ProjectsController, :with_license, feature_category: :groups_and_projects do
  let_it_be(:default_organization) { create(:organization, :default) } # rubocop:disable Gitlab/RSpec/AvoidCreateDefaultOrganization -- specs read Amazon Q instance settings stored on the default organization
  let_it_be(:user) { create(:user, :with_namespace) }
  let_it_be(:project) { create(:project, maintainers: user) }

  before do
    sign_in(user)
  end

  context 'when Amazon Q is connected' do
    let_it_be(:integration) { create(:amazon_q_integration, instance: false, project: project) }

    let(:params) do
      {
        project: {
          amazon_q_auto_review_enabled: true,
          project_setting_attributes: { duo_features_enabled: 'true' }
        }
      }
    end

    before do
      allow(::Ai::AmazonQ).to receive(:connected?).and_return(true)
    end

    it 'changes auto_review_enabled field of the integration' do
      expect { put project_url(project, params) }.to change {
        project.amazon_q_integration.reload.auto_review_enabled
      }.from(false).to(true)
    end
  end

  context 'when viewing the new page' do
    it 'is successful' do
      get new_project_url

      expect(response).to have_gitlab_http_status(:ok)
    end
  end

  describe 'PUT #transfer_personal' do
    let_it_be(:user_namespace) { create(:user_namespace) }
    let_it_be(:personal_project) { create(:project, namespace: user_namespace) }

    context 'when is a project owner' do
      let_it_be(:group) { create(:group) }

      before_all do
        personal_project.add_owner(user)
      end

      before do
        allow_next_instance_of(Groups::CreateService) do |instance|
          allow(instance).to receive(:execute).and_return(ServiceResponse.success(payload: { group: group }))
        end
      end

      context 'when transfer is successful' do
        before_all do
          group.add_owner(user)
        end

        it 'returns link to a new group and group name' do
          # Default 100 -> 102: resolve_project_access_from_memberships looks up memberships and shares (!263759).
          allow(Gitlab::QueryLimiting::Transaction).to receive(:threshold).and_return(102)

          put project_transfer_personal_path(personal_project)

          expect(json_response['redirect_to']).to eq(group_billings_path(group))
          expect(json_response['group_name']).to eq(group.name)
        end
      end

      context 'when transfer is not successful' do
        it 'returns error message' do
          put project_transfer_personal_path(personal_project)

          expect(json_response['message']).to eq('Personal project cannot be transferred')
        end
      end
    end

    context 'when user does not have permission to change namespace' do
      before_all do
        personal_project.add_developer(user)
      end

      it 'denies access' do
        put project_transfer_personal_path(personal_project)

        expect(response).to have_gitlab_http_status(:not_found)
      end
    end
  end

  describe 'GET #edit' do
    it_behaves_like 'pushes frontend feature flag', :policy_store_setting_enforcement do
      let(:make_request) { get edit_project_path(project) }
      let(:feature_args) { [project.root_ancestor] }
    end
  end

  describe 'PUT #update with a warn-mode settings policy', feature_category: :security_policy_management do
    include Govern::SettingsGateHelpers

    let(:policy) do
      build_stubbed(:govern_policy, :without_namespace, organization: project.organization,
        trigger_type: 'project.before_settings_update', mode: :warn, name: 'Baseline',
        rules: [{ 'type' => 'setting_validation', 'rego' => 'package governance',
                  'value' => { 'setting' => 'request_access_enabled', 'value' => false } }],
        actions: [{ 'type' => 'block', 'value' => { 'message' => 'Keep request access off.' } }])
    end

    def stub_evaluation
      stub_settings_gate_evaluation(policy: policy, setting: 'request_access_enabled',
        expected: false, actual: true, message: 'Keep request access off.')
    end

    before do
      stub_application_setting(policy_store_experiment_enabled: true)
      stub_licensed_features(security_orchestration_policies: true)
      stub_feature_flags(security_policies_v2: true)
      ::Organizations::OrganizationSetting.for(project.organization_id).update!(policy_store_experiment_enabled: true)
      Project.find(project.id).update!(request_access_enabled: false)
    end

    it 'saves the change and shows the warn message as a warning flash', :aggregate_failures do
      stub_evaluation

      put project_url(project), params: { project: { request_access_enabled: '1' } }

      expect(response).to redirect_to(edit_project_path(project, anchor: 'js-general-project-settings'))
      expect(flash[:warning]).to eq('Keep request access off.')
    end
  end
end
