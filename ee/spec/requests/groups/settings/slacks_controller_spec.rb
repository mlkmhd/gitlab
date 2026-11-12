# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Groups::Settings::SlacksController, feature_category: :integrations do
  let_it_be(:group) { create(:group) }
  let_it_be(:project) { create(:project, group: group) }
  let_it_be(:owner) { create(:user, owner_of: group) }
  let_it_be(:maintainer) { create(:user, maintainer_of: group) }

  let(:path) { duo_group_group_settings_slack_path(group) }
  let(:user) { owner }

  before_all do
    create(:slack_integration, :project, project: project, team_id: 'T_ACME', team_name: 'Acme')
  end

  before do
    stub_application_setting(instance_level_ai_beta_features_enabled: true)
    sign_in(user)
  end

  shared_examples 'not found without GitLab Duo in Slack for the user' do
    context 'with experiment and beta features turned off' do
      before do
        stub_application_setting(instance_level_ai_beta_features_enabled: false)
      end

      it 'is not found' do
        request

        expect(response).to have_gitlab_http_status(:not_found)
      end
    end
  end

  describe 'PUT duo_group' do
    subject(:request) { put path, params: { team_id: 'T_ACME', enabled: enabled }, as: :json }

    let(:enabled) { true }

    it 'turns GitLab Duo on for the workspace and answers with the page data and its row' do
      request

      expect(response).to have_gitlab_http_status(:ok)
      expect(Integrations::SlackWorkspace::Workspace.for_team('T_ACME').duo_namespace).to eq(group)
      expect(json_response['workspaces']).to contain_exactly(include('team_id' => 'T_ACME', 'state' => 'on_here'))
      expect(json_response['updated_workspace']).to include('team_id' => 'T_ACME', 'state' => 'on_here')
    end

    context 'for a workspace installed only in another group' do
      let_it_be(:other_group) { create(:group) }

      before_all do
        create(:slack_integration, :group, group: other_group, team_id: 'T_OTHER_ONLY')
      end

      it 'refuses to claim it' do
        put path, params: { team_id: 'T_OTHER_ONLY', enabled: true }, as: :json

        expect(response).to have_gitlab_http_status(:unprocessable_entity)
        expect(json_response['reason']).to eq('workspace_not_connected')
        expect(Integrations::SlackWorkspace::Workspace.for_team('T_OTHER_ONLY')).to be_nil
      end

      it "doesn't say whether, or where, it runs GitLab Duo, and keeps the claim" do
        create(:slack_workspace, team_id: 'T_OTHER_ONLY', duo_namespace: other_group)

        put path, params: { team_id: 'T_OTHER_ONLY', enabled: false }, as: :json

        expect(response).to have_gitlab_http_status(:unprocessable_entity)
        expect(json_response['reason']).to eq('workspace_not_connected')
        expect(Integrations::SlackWorkspace::Workspace.for_team('T_OTHER_ONLY').duo_namespace).to eq(other_group)
      end
    end

    context 'when turning it off' do
      let(:enabled) { false }

      it 'deletes the claim' do
        create(:slack_workspace, team_id: 'T_ACME', duo_namespace: group)

        request

        expect(response).to have_gitlab_http_status(:ok)
        expect(Integrations::SlackWorkspace::Workspace.for_team('T_ACME')).to be_nil
      end
    end

    context 'without a valid `enabled`' do
      let_it_be(:workspace) { create(:slack_workspace, team_id: 'T_ACME', duo_namespace: group) }

      where(:enabled) { [nil, 'maybe'] }

      with_them do
        it 'changes nothing' do
          request

          expect(response).to have_gitlab_http_status(:bad_request)
          expect(json_response['reason']).to eq('invalid_enabled')
          expect(workspace.reload.duo_namespace).to eq(group)
        end
      end
    end

    # Unlike the list, a change is refused with the reason, as the services refuse every other change.
    context 'on a subgroup' do
      let_it_be(:subgroup) { create(:group, parent: group) }

      it 'refuses it as not a top-level group and changes nothing' do
        put duo_group_group_settings_slack_path(subgroup), params: { team_id: 'T_ACME', enabled: true }, as: :json

        expect(response).to have_gitlab_http_status(:unprocessable_entity)
        expect(json_response['reason']).to eq('not_top_level_group')
        expect(Integrations::SlackWorkspace::Workspace.for_team('T_ACME')).to be_nil
      end
    end

    context 'as a Maintainer' do
      let(:user) { maintainer }

      it 'is not found' do
        request

        expect(response).to have_gitlab_http_status(:not_found)
      end
    end

    context 'with the feature flag off' do
      before do
        stub_feature_flags(slack_duo_group: false)
      end

      it 'is not found' do
        request

        expect(response).to have_gitlab_http_status(:not_found)
      end
    end

    context 'with the feature flag on for another group only' do
      before do
        stub_feature_flags(slack_duo_group: create(:group))
      end

      it 'is not found' do
        request

        expect(response).to have_gitlab_http_status(:not_found)
      end
    end

    it_behaves_like 'not found without GitLab Duo in Slack for the user'

    context 'without GitLab Duo in Slack for the user' do
      before do
        stub_application_setting(instance_level_ai_beta_features_enabled: false)
      end

      it 'keeps GitLab Duo off for the workspace' do
        request

        expect(Integrations::SlackWorkspace::Workspace.for_team('T_ACME')).to be_nil
      end
    end
  end

  describe 'GET duo_group' do
    before do
      stub_const('Integrations::SlackWorkspace::DuoWorkspacesPresenter::PAGE_SIZE', 1)
      create(:slack_integration, :project, project: create(:project, group: group), team_id: 'T_OTHER')
    end

    it 'answers with the first page' do
      get path, as: :json

      expect(response).to have_gitlab_http_status(:ok)
      expect(json_response['workspaces'].pluck('team_id')).to eq(%w[T_ACME])
      expect(json_response['more_count']).to eq(1)
    end

    it 'answers with the page from `offset`' do
      get path, params: { offset: 1 }, as: :json

      expect(json_response.keys).to contain_exactly('workspaces', 'more_count')
      expect(json_response['workspaces'].pluck('team_id')).to eq(%w[T_OTHER])
      expect(json_response['more_count']).to eq(0)
    end

    it 'never answers with more than a page' do
      get path, params: { offset: -1, limit: 1000 }, as: :json

      expect(json_response['workspaces'].size).to eq(1)
    end

    context 'on a subgroup page' do
      let_it_be(:subgroup) { create(:group, parent: group) }

      it 'is not found' do
        get duo_group_group_settings_slack_path(subgroup), as: :json

        expect(response).to have_gitlab_http_status(:not_found)
      end
    end

    context 'as a Maintainer' do
      let(:user) { maintainer }

      it 'is not found' do
        get path, as: :json

        expect(response).to have_gitlab_http_status(:not_found)
      end
    end

    context 'with the feature flag off' do
      before do
        stub_feature_flags(slack_duo_group: false)
      end

      it 'is not found' do
        get path, as: :json

        expect(response).to have_gitlab_http_status(:not_found)
      end
    end

    it_behaves_like 'not found without GitLab Duo in Slack for the user' do
      subject(:request) { get path, as: :json }
    end
  end
end
