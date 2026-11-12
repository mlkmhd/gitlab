# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Integrations::SlackInstallation::GroupService, feature_category: :integrations do
  let_it_be(:organization) { create(:organization) }
  let_it_be_with_refind(:group) { create(:group, organization: organization) }
  let_it_be(:owner) { create(:user, owner_of: group) }

  let(:team_id) { 'T_ACME' }
  let(:target) { group }
  let(:current_user) { owner }

  subject(:install) do
    service = described_class.new(target, current_user: current_user, params: { code: 'code' })
    allow(service).to receive(:exchange_slack_token).and_return(
      'ok' => true, 'bot_user_id' => 'U_BOT', 'access_token' => 'xoxb-token', 'scope' => 'commands',
      'team' => { 'id' => team_id, 'name' => 'Acme' }, 'authed_user' => { 'id' => 'U_OWNER' }
    )
    service.execute
  end

  before do
    stub_application_setting(slack_app_enabled: true)
  end

  def duo_group
    Integrations::SlackWorkspace::Workspace.for_team(team_id)&.duo_namespace
  end

  it 'claims the workspace for GitLab Duo on the first install on a top-level group' do
    expect(install).to be_success
    expect(duo_group).to eq(group)
  end

  it 'does not claim it again on a reinstall after an Owner turned GitLab Duo off' do
    install
    Integrations::SlackWorkspace::Workspace.for_team(team_id).destroy!

    described_class.new(group, current_user: owner, params: { code: 'code' }).tap do |service|
      allow(service).to receive(:exchange_slack_token).and_return(
        'ok' => true, 'bot_user_id' => 'U_BOT', 'access_token' => 'xoxb-token', 'scope' => 'commands',
        'team' => { 'id' => team_id, 'name' => 'Acme' }, 'authed_user' => { 'id' => 'U_OWNER' }
      )
    end.execute

    expect(duo_group).to be_nil
  end

  context 'for a subgroup' do
    let(:target) { create(:group, parent: group).tap { |subgroup| subgroup.add_owner(owner) } }

    it 'does not claim the workspace' do
      expect(install).to be_success
      expect(duo_group).to be_nil
    end
  end

  context 'when the workspace is installed for the instance' do
    before do
      create(:slack_integration, :instance, organization: organization, team_id: team_id)
    end

    it 'leaves the choice to the administrator' do
      expect(Gitlab::IntegrationsLogger).to receive(:info).with(hash_including(
        message: 'Slack Duo group not claimed on install', claim_failure_reason: :managed_by_admin,
        Labkit::Fields::GL_NAMESPACE_ID => group.id, slack_workspace_id: team_id
      ))

      expect(install).to be_success
      expect(duo_group).to be_nil
    end

    context 'when an administrator installs', :enable_admin_mode do
      let(:current_user) { create(:admin) }

      it 'does not claim the workspace' do
        expect(install).to be_success
        expect(duo_group).to be_nil
      end
    end
  end

  context 'when another group runs GitLab Duo for the workspace' do
    let_it_be(:other_group) { create(:group, organization: organization) }

    before do
      create(:slack_integration, :group, group: other_group, team_id: team_id)
      create(:slack_workspace, team_id: team_id, duo_namespace: other_group)
    end

    it 'installs the app, logs the refused claim and keeps the other group' do
      expect(Gitlab::IntegrationsLogger).to receive(:info).with(hash_including(
        message: 'Slack Duo group not claimed on install', claim_failure_reason: :claimed_by_another_group
      ))

      expect(install).to be_success
      expect(duo_group).to eq(other_group)
    end
  end

  context 'when claiming fails' do
    before do
      allow(Integrations::SlackWorkspace::EnableDuoGroupService).to receive(:new).and_raise(StandardError)
    end

    it 'still installs the app' do
      expect(Gitlab::ErrorTracking).to receive(:track_exception)

      expect(install).to be_success
    end
  end

  context 'when the alias is taken in the workspace' do
    before do
      create(:slack_integration, :group, group: create(:group, organization: organization), team_id: team_id,
        alias: group.full_path)
    end

    it 'installs with the fallback alias and claims the workspace', :aggregate_failures do
      expect(install).to be_success
      expect(SlackIntegration.find_by!(group_id: group.id, team_id: team_id).alias)
        .to eq("#{group.full_path}/g-#{group.id}")
      expect(duo_group).to eq(group)
    end
  end

  # Nothing writes to `slack_workspaces` while the flag is off. The Cells discussion for the `team_id` claim
  # relies on that: https://gitlab.com/gitlab-org/gitlab/-/work_items/633611
  context 'with the feature flag off' do
    before do
      stub_feature_flags(slack_duo_group: false)
    end

    it 'installs the app and creates no Slack workspace rows', :aggregate_failures do
      expect(Gitlab::ErrorTracking).not_to receive(:track_exception)

      expect { expect(install).to be_success }.not_to change { Integrations::SlackWorkspace::Workspace.count }
    end
  end

  context 'with the feature flag on for another top-level group only' do
    before do
      stub_feature_flags(slack_duo_group: create(:group))
    end

    it 'creates no Slack workspace rows' do
      expect { install }.not_to change { Integrations::SlackWorkspace::Workspace.count }
    end
  end
end
