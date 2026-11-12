# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Admin::SlacksController, :enable_admin_mode, feature_category: :integrations do
  let_it_be(:organization) { create(:common_organization) }
  let_it_be(:admin) { create(:admin, organizations: [organization]) }
  let_it_be(:group) { create(:group, organization: organization) }

  let(:path) { duo_group_admin_application_settings_slack_path }

  before_all do
    create(:slack_integration, :instance, organization: organization, team_id: 'T_INSTANCE', team_name: 'Acme')
  end

  before do
    stub_application_setting(instance_level_ai_beta_features_enabled: true)
    sign_in(admin)
  end

  def duo_group
    Integrations::SlackWorkspace::Workspace.for_team('T_INSTANCE')&.duo_namespace
  end

  describe 'PUT duo_group' do
    it 'chooses the Duo group of the instance workspace and answers with the page data', :aggregate_failures do
      put path, params: { team_id: 'T_INSTANCE', group_id: group.id }, as: :json

      expect(response).to have_gitlab_http_status(:ok)
      expect(duo_group).to eq(group)
      expect(json_response).to include('scope' => 'admin', 'state' => 'on', 'team_id' => 'T_INSTANCE',
        'duo_group' => include('id' => group.id))
    end

    it 'moves GitLab Duo to another group', :aggregate_failures do
      other_group = create(:group, organization: organization)
      create(:slack_workspace, team_id: 'T_INSTANCE', duo_namespace: group)

      put path, params: { team_id: 'T_INSTANCE', group_id: other_group.id }, as: :json

      expect(response).to have_gitlab_http_status(:ok)
      expect(duo_group).to eq(other_group)
    end

    it 'turns GitLab Duo off without a group', :aggregate_failures do
      create(:slack_workspace, team_id: 'T_INSTANCE', duo_namespace: group)

      put path, params: { team_id: 'T_INSTANCE', group_id: '' }, as: :json

      expect(response).to have_gitlab_http_status(:ok)
      expect(duo_group).to be_nil
      expect(json_response).to include('state' => 'off')
    end

    it 'turns GitLab Duo off with an explicit null group', :aggregate_failures do
      create(:slack_workspace, team_id: 'T_INSTANCE', duo_namespace: group)

      put path, params: { team_id: 'T_INSTANCE', group_id: nil }, as: :json

      expect(response).to have_gitlab_http_status(:ok)
      expect(duo_group).to be_nil
    end

    it 'keeps GitLab Duo on without a group_id', :aggregate_failures do
      create(:slack_workspace, team_id: 'T_INSTANCE', duo_namespace: group)

      put path, params: { team_id: 'T_INSTANCE' }, as: :json

      expect(response).to have_gitlab_http_status(:bad_request)
      expect(json_response['reason']).to eq('missing_group')
      expect(duo_group).to eq(group)
    end

    it 'explains a refused group', :aggregate_failures do
      archived = create(:group, :archived, organization: organization)

      put path, params: { team_id: 'T_INSTANCE', group_id: archived.id }, as: :json

      expect(response).to have_gitlab_http_status(:unprocessable_entity)
      expect(json_response['reason']).to eq('inactive_group')
      expect(duo_group).to be_nil
    end

    it 'is not found for a workspace the instance did not install', :aggregate_failures do
      create(:slack_integration, :group, group: group, team_id: 'T_GROUP')

      put path, params: { team_id: 'T_GROUP', group_id: group.id }, as: :json

      expect(response).to have_gitlab_http_status(:not_found)
      expect(Integrations::SlackWorkspace::Workspace.for_team('T_GROUP')).to be_nil
    end

    it 'is not found for a subgroup', :aggregate_failures do
      put path, params: { team_id: 'T_INSTANCE', group_id: create(:group, parent: group).id }, as: :json

      expect(response).to have_gitlab_http_status(:not_found)
      expect(duo_group).to be_nil
    end

    it 'is not found for a group of another organization', :aggregate_failures do
      put path, params: { team_id: 'T_INSTANCE', group_id: create(:group, organization: create(:organization)).id },
        as: :json

      expect(response).to have_gitlab_http_status(:not_found)
      expect(duo_group).to be_nil
    end

    it 'is not found for a non-administrator', :aggregate_failures do
      sign_in(create(:user, owner_of: group))

      put path, params: { team_id: 'T_INSTANCE', group_id: group.id }, as: :json

      expect(response).to have_gitlab_http_status(:not_found)
      expect(duo_group).to be_nil
    end

    context 'with experiment and beta features turned off' do
      before do
        stub_application_setting(instance_level_ai_beta_features_enabled: false)
      end

      it 'is not found', :aggregate_failures do
        put path, params: { team_id: 'T_INSTANCE', group_id: group.id }, as: :json

        expect(response).to have_gitlab_http_status(:not_found)
        expect(duo_group).to be_nil
      end
    end

    context 'with the feature flag off for the instance' do
      before do
        stub_feature_flags(slack_duo_group: group)
      end

      it 'is not found', :aggregate_failures do
        put path, params: { team_id: 'T_INSTANCE', group_id: group.id }, as: :json

        expect(response).to have_gitlab_http_status(:not_found)
        expect(duo_group).to be_nil
      end
    end
  end
end
