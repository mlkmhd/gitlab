# frozen_string_literal: true

require 'spec_helper'

RSpec.describe SlackIntegration, feature_category: :integrations do
  let_it_be_with_reload(:integration) { create(:slack_integration) }

  describe "Associations" do
    it { is_expected.to belong_to(:integration) }
  end

  describe 'constant' do
    it 'is expected that DEFAULT_ALIAS is defined with the correct value' do
      expect(described_class::ORGANIZATION_ALIAS).to eq('gitlab-organization')
    end
  end

  describe '.scopes_for' do
    it 'returns SCOPES when duo_enabled is false' do
      expect(described_class.scopes_for(duo_enabled: false)).to eq(described_class::SCOPES)
    end

    it 'returns DUO_SCOPES and AGENT_APP_SCOPES when duo_enabled is true' do
      expect(described_class.scopes_for(duo_enabled: true))
        .to eq(described_class::DUO_SCOPES + described_class::AGENT_APP_SCOPES)
    end

    it 'includes the base scopes in DUO_SCOPES' do
      expect(described_class::DUO_SCOPES).to include(*described_class::SCOPES)
    end

    it 'includes the Duo-specific scopes in DUO_SCOPES' do
      expect(described_class::DUO_SCOPES).to include(
        described_class::SCOPE_APP_MENTIONS_READ,
        described_class::SCOPE_CHANNELS_HISTORY,
        described_class::SCOPE_GROUPS_HISTORY,
        described_class::SCOPE_REACTIONS_WRITE
      )
    end

    it 'includes the agent app scopes in AGENT_APP_SCOPES' do
      expect(described_class::AGENT_APP_SCOPES).to contain_exactly(
        described_class::SCOPE_IM_HISTORY,
        described_class::SCOPE_MPIM_HISTORY,
        described_class::SCOPE_ASSISTANT_WRITE
      )
    end

    context 'when the slack_duo_agent_app release flag is disabled' do
      before do
        stub_feature_flags(slack_duo_agent_app: false)
      end

      it 'returns SCOPES when duo_enabled is false' do
        expect(described_class.scopes_for(duo_enabled: false)).to eq(described_class::SCOPES)
      end

      it 'returns only DUO_SCOPES when duo_enabled is true' do
        expect(described_class.scopes_for(duo_enabled: true)).to eq(described_class::DUO_SCOPES)
      end
    end
  end

  describe '.agent_app_enabled?' do
    it 'is true when the slack_duo_agent_app release flag is enabled' do
      expect(described_class.agent_app_enabled?).to be(true)
    end

    it 'is false when the slack_duo_agent_app release flag is disabled' do
      stub_feature_flags(slack_duo_agent_app: false)

      expect(described_class.agent_app_enabled?).to be(false)
    end
  end

  describe '.organization_alias' do
    it 'returns organization alias with org_id provided' do
      expect(described_class.organization_alias(1)).to eq('gitlab-organization-1')
    end

    context 'when organization_id is not an integer' do
      it 'raises ArgumentError', :aggregate_failures do
        expect { described_class.organization_alias(nil) }
          .to raise_error ArgumentError, 'organization_id must be an Integer'

        expect { described_class.organization_alias('1') }
          .to raise_error ArgumentError, 'organization_id must be an Integer'
      end
    end
  end

  describe 'authorized_scope_names' do
    subject(:slack_integration) { integration }

    it 'accepts assignment to nil' do
      slack_integration.update!(authorized_scope_names: nil)

      expect(slack_integration.authorized_scope_names).to be_empty
    end

    it 'accepts assignment to a string' do
      slack_integration.update!(authorized_scope_names: 'foo')

      expect(slack_integration.authorized_scope_names).to contain_exactly('foo')
    end

    it 'accepts assignment to an array of strings' do
      slack_integration.update!(authorized_scope_names: %w[foo bar])

      expect(slack_integration.authorized_scope_names).to contain_exactly('foo', 'bar')
    end

    it 'accepts assignment to a comma-separated string' do
      slack_integration.update!(authorized_scope_names: 'foo,bar')

      expect(slack_integration.authorized_scope_names).to contain_exactly('foo', 'bar')
    end

    it 'strips white-space' do
      slack_integration.update!(authorized_scope_names: 'foo , bar,baz')

      expect(slack_integration.authorized_scope_names).to contain_exactly('foo', 'bar', 'baz')
    end

    it 'creates the api scopes in the organization the record is sharded to' do
      slack_integration.update!(authorized_scope_names: 'foo')

      expect(slack_integration.slack_api_scopes).to contain_exactly(
        have_attributes(name: 'foo', organization_id: slack_integration.organization_id_from_parent)
      )
    end
  end

  describe '#organization_id_from_parent' do
    context 'when sharded to an organization' do
      let_it_be(:slack_integration) { create(:slack_integration, :instance) }

      it 'returns its own organization_id' do
        expect(slack_integration.organization_id_from_parent).to eq(slack_integration.organization_id)
      end
    end

    context 'when sharded to a group' do
      let_it_be(:slack_integration) { create(:slack_integration, :group) }

      it "returns the group's organization_id" do
        expect(slack_integration.organization_id_from_parent).to eq(slack_integration.group.organization_id)
      end
    end

    context 'when sharded to a project' do
      let_it_be(:slack_integration) { create(:slack_integration, :project) }

      it "returns the project's organization_id" do
        expect(slack_integration.organization_id_from_parent).to eq(slack_integration.project.organization_id)
      end
    end
  end

  describe 'all_features_supported?/upgrade_needed?' do
    subject(:slack_integration) { integration }

    context 'with enough scopes' do
      before do
        slack_integration.update!(authorized_scope_names: %w[chat:write.public chat:write commands])
      end

      it { is_expected.to be_all_features_supported }
      it { is_expected.not_to be_upgrade_needed }
    end

    %w[chat:write.public chat:write].each do |scope_name|
      context "without #{scope_name}" do
        before do
          scopes = %w[chat:write.public chat:write] - [scope_name]
          slack_integration.update!(authorized_scope_names: scopes)
        end

        it { is_expected.not_to be_all_features_supported }
        it { is_expected.to be_upgrade_needed }
      end
    end
  end

  describe 'feature_available?' do
    subject(:slack_integration) { integration }

    describe ':duo' do
      let(:duo_scopes) { described_class::DUO_SCOPES + described_class::AGENT_APP_SCOPES }

      it 'is true with the Duo and agent app scopes' do
        slack_integration.update!(authorized_scope_names: duo_scopes)

        expect(slack_integration).to be_feature_available(:duo)
      end

      it 'is false with only the base scopes' do
        slack_integration.update!(authorized_scope_names: described_class::SCOPES)

        expect(slack_integration).not_to be_feature_available(:duo)
      end

      it 'is false without the agent app scopes' do
        slack_integration.update!(authorized_scope_names: described_class::DUO_SCOPES)

        expect(slack_integration).not_to be_feature_available(:duo)
      end

      context 'when the slack_duo_agent_app release flag is disabled' do
        before do
          stub_feature_flags(slack_duo_agent_app: false)
        end

        it 'is true without the agent app scopes' do
          slack_integration.update!(authorized_scope_names: described_class::DUO_SCOPES)

          expect(slack_integration).to be_feature_available(:duo)
        end
      end
    end

    context 'without any scopes' do
      it 'is always true for :commands' do
        expect(slack_integration).to be_feature_available(:commands)
      end

      it 'is always false for others' do
        expect(slack_integration).not_to be_feature_available(:notifications)
        expect(slack_integration).not_to be_feature_available(:foo)
      end
    end

    context 'with enough scopes for notifications' do
      before do
        slack_integration.update!(authorized_scope_names: %w[chat:write.public chat:write foo])
      end

      it 'only has the correct features' do
        expect(slack_integration).to be_feature_available(:commands)
        expect(slack_integration).to be_feature_available(:notifications)
        expect(slack_integration).not_to be_feature_available(:foo)
      end
    end

    context 'with enough scopes for commands' do
      before do
        slack_integration.update!(authorized_scope_names: %w[commands foo])
      end

      it 'only has the correct features' do
        expect(slack_integration).to be_feature_available(:commands)
        expect(slack_integration).not_to be_feature_available(:notifications)
        expect(slack_integration).not_to be_feature_available(:foo)
      end
    end

    context 'with all scopes' do
      before do
        slack_integration.update!(authorized_scope_names: %w[commands chat:write chat:write.public])
      end

      it 'only has the correct features' do
        expect(slack_integration).to be_feature_available(:commands)
        expect(slack_integration).to be_feature_available(:notifications)
        expect(slack_integration).not_to be_feature_available(:foo)
      end
    end
  end

  describe '#to_database_hash' do
    subject(:slack_integration) { integration }

    it 'includes the correct attributes' do
      expect(slack_integration.to_database_hash.keys).to match_array(described_class::DATABASE_ATTRIBUTES)
    end
  end

  it 'toggles the integration to active when created' do
    integration = create(:gitlab_slack_application_integration, active: false, slack_integration: nil)

    expect { create(:slack_integration, integration: integration) }.to change { integration.reload.active }.to(true)
  end

  it 'toggles the integration to inactive when destroyed' do
    integration = create(:gitlab_slack_application_integration)

    expect { integration.slack_integration.destroy! }.to change { integration.reload.active }.to(false)
  end

  describe 'Scopes' do
    let_it_be(:slack_integration) { integration }
    let_it_be(:legacy_slack_integration) { create(:slack_integration, :legacy) }

    describe '#with_bot' do
      it 'returns records with bot data' do
        expect(described_class.with_bot).to contain_exactly(slack_integration)
      end
    end

    describe '#by_team' do
      it 'returns records with shared team_id' do
        team_id = slack_integration.team_id
        team_slack_integration = create(:slack_integration, team_id: team_id)

        expect(described_class.by_team(team_id)).to contain_exactly(slack_integration, team_slack_integration)
      end
    end

    describe '#by_integration' do
      it 'returns records by the integration' do
        integration = legacy_slack_integration.integration

        expect(described_class.by_integration(integration)).to contain_exactly(legacy_slack_integration)
      end
    end
  end

  describe 'workspaces of a hierarchy' do
    let_it_be(:organization) { create(:organization) }
    let_it_be(:group) { create(:group, organization: organization) }
    let_it_be(:subgroup) { create(:group, parent: group) }
    let_it_be(:project) { create(:project, group: subgroup) }
    let_it_be(:other_group) { create(:group, organization: organization) }

    let_it_be(:instance_install) do
      create(:slack_integration, :instance, organization: organization, team_id: 'T_INSTANCE', team_name: 'Old',
        alias: 'a-instance')
    end

    let_it_be(:group_install) do
      create(:slack_integration, :group, group: subgroup, team_id: 'T_SUB', team_name: 'Sub', alias: 'a-sub')
    end

    let_it_be(:project_install) do
      create(:slack_integration, :project, project: project, team_id: 'T_INSTANCE', team_name: 'New',
        alias: 'b-project')
    end

    let_it_be(:other_install) do
      create(:slack_integration, :group, group: other_group, team_id: 'T_SUB', alias: 'b-other')
    end

    it 'finds installs by level' do
      expect(described_class.instance_level).to include(instance_install)
      expect(described_class.instance_level).not_to include(group_install, project_install)
      expect(described_class.instance_level_in(organization)).to contain_exactly(instance_install)
      expect(described_class.for_groups_in(group)).to contain_exactly(group_install)
      expect(described_class.for_projects_in(group)).to contain_exactly(project_install)
    end

    it 'lists team IDs' do
      expect(described_class.by_team(%w[T_INSTANCE T_SUB]).team_ids).to eq(%w[T_INSTANCE T_SUB])
    end

    describe '.team_names' do
      it 'names each workspace after its first install by alias, in the current scope' do
        expect(described_class.team_names(%w[T_INSTANCE T_SUB T_NONE])).to eq('T_INSTANCE' => 'Old', 'T_SUB' => 'Sub')
        expect(described_class.for_projects_in(group).team_names(%w[T_INSTANCE])).to eq('T_INSTANCE' => 'New')
        expect(described_class.team_names([])).to eq({})
      end
    end

    describe '.sampled_team_ids_with_scope' do
      let(:scope_name) { described_class::SCOPE_APP_MENTIONS_READ }

      it 'lists the workspaces whose first install by alias was granted the scope' do
        group_install.update!(authorized_scope_names: [scope_name])

        expect(described_class.sampled_team_ids_with_scope(%w[T_INSTANCE T_SUB], scope_name)).to eq(%w[T_SUB])
      end

      it 'does not look past the first install' do
        other_install.update!(authorized_scope_names: [scope_name])

        expect(described_class.sampled_team_ids_with_scope(%w[T_SUB], scope_name)).to be_empty
      end
    end
  end

  describe 'Validations' do
    it { is_expected.to validate_presence_of(:team_id) }
    it { is_expected.to validate_presence_of(:team_name) }
    it { is_expected.to validate_presence_of(:alias) }
    it { is_expected.to validate_presence_of(:user_id) }
    it { is_expected.to validate_presence_of(:integration) }
    it { is_expected.to validate_length_of(:bot_access_token).is_at_most(255) }

    specify 'bot_access_token length validation does not invalidate existing records' do
      slack_integration = create(:slack_integration)
      slack_integration.bot_access_token = 'A' * 260
      slack_integration.save!(validate: false)

      expect(slack_integration.reload).to be_valid
    end
  end
end
