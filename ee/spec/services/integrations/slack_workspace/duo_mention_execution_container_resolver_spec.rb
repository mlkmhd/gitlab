# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Integrations::SlackWorkspace::DuoMentionExecutionContainerResolver, feature_category: :integrations do
  let_it_be(:organization) { create(:organization) }
  let_it_be(:group) { create(:group, organization: organization) }
  let_it_be(:user) { create(:user, developer_of: group) }

  let(:team_id) { 'T_ACME' }

  subject(:result) do
    described_class.new(
      team_id: team_id, workspace: Integrations::SlackWorkspace::Workspace.for_team(team_id), user: user
    ).execute
  end

  before do
    create(:slack_integration, :group, group: group, team_id: team_id)
  end

  context 'without a Duo group' do
    it 'refuses without naming the group that installed the app' do
      expect(result.reason).to eq(:duo_group_not_set_up)
      expect(result.payload[:context]).to eq(duo_group_path: true)
    end

    context 'when the workspace is installed for an instance' do
      before do
        stub_saas_features(gitlab_com_subscriptions: false)
        create(:slack_integration, :instance, organization: create(:organization), team_id: team_id)
      end

      it 'names the administrator, whichever install row the event came from' do
        expect(result.payload[:context]).to include(
          setup_by: 'admin',
          setup_url: end_with('/admin/application_settings/integrations/gitlab_slack_application/edit')
        )
      end
    end

    context 'on GitLab.com' do
      before do
        stub_saas_features(gitlab_com_subscriptions: true)
        create(:slack_integration, :instance, organization: create(:organization), team_id: team_id)
      end

      it 'names no administrator' do
        expect(result.payload[:context]).to eq(duo_group_path: true)
      end
    end
  end

  describe '.experiment_features_required?' do
    subject { described_class.experiment_features_required? }

    it { is_expected.to be(true) }

    context 'when the Slack flow is GA' do
      before do
        allow(Ai::Catalog::FoundationalFlow.slack_assistant_v1).to receive(:feature_maturity).and_return('ga')
      end

      it { is_expected.to be(false) }
    end
  end

  describe '.refusal' do
    subject(:refusal) { described_class.refusal(group, user) }

    before do
      allow_next_instance_of(Integrations::SlackWorkspace::DuoRequirements) do |requirements|
        allow(requirements).to receive_messages(duo_features_enabled?: duo, agent_platform_enabled?: platform)
      end
      allow(::Gitlab::Llm::StageCheck).to receive(:available?).with(group, :duo_workflow).and_return(licensed)
      allow(user).to receive(:allowed_to_use?).with(:duo_agent_platform, root_namespace: group).and_return(seat)
    end

    # A group without a GitLab Duo subscription passes the settings checks but the platform refuses; without
    # its own branch the reply would blame the user's role.
    where(:duo, :platform, :licensed, :seat, :expected) do
      [
        [false, true, true, true, 'duo_features_off'],
        [true, false, true, true, 'agent_platform_off'],
        [true, true, false, true, 'not_licensed'],
        [true, true, true, false, 'seat'],
        [true, true, true, true, 'role']
      ]
    end

    with_them do
      it { is_expected.to eq(expected) }
    end
  end

  context 'with a Duo group' do
    before do
      create(:slack_workspace, team_id: team_id, duo_namespace: group)
      allow_next_instance_of(Integrations::SlackWorkspace::DuoRequirements) do |requirements|
        allow(requirements).to receive(:experiment_features_enabled?).and_return(experiments)
      end
    end

    let(:experiments) { true }

    it 'runs in the group' do
      expect(result).to be_success
      expect(result.payload[:group]).to eq(group)
      expect(result.payload[:context]).to include(duo_group_path: true, duo_group_name: group.full_name)
      expect(result.payload[:context]).not_to have_key(:duo_group_refusal)
    end

    context 'when the user cannot read the group' do
      before do
        allow(Ability).to receive(:allowed?).and_call_original
        allow(Ability).to receive(:allowed?).with(user, :read_group, group).and_return(false)
      end

      it 'does not name it' do
        expect(result).to be_success
        expect(result.payload[:context]).not_to have_key(:duo_group_name)
      end
    end

    context 'when experiment and beta features are off in the group' do
      let(:experiments) { false }

      it 'refuses' do
        expect(result.reason).to eq(:duo_group_experiments_off)
      end

      it 'runs in the group once the gate is dropped' do
        allow(described_class).to receive(:experiment_features_required?).and_return(false)

        expect(result).to be_success
      end
    end
  end

  context 'with a claim that no longer holds' do
    before do
      create(:slack_workspace, team_id: team_id, duo_namespace: create(:group, organization: organization))
    end

    it 'releases it and refuses' do
      expect(result.reason).to eq(:duo_group_not_set_up)
      expect(Integrations::SlackWorkspace::Workspace.for_team(team_id)).to be_nil
    end
  end

  context 'with a claim of a group that was archived' do
    let(:team_id) { 'T_ARCHIVED' }

    before do
      archived = create(:group, organization: organization)
      create(:slack_integration, :group, group: archived, team_id: team_id)
      create(:slack_workspace, team_id: team_id, duo_namespace: archived)
      archived.namespace_settings.update!(archived: true)
    end

    it 'releases it and refuses' do
      expect(result.reason).to eq(:duo_group_not_set_up)
      expect(Integrations::SlackWorkspace::Workspace.for_team(team_id)).to be_nil
    end
  end
end
