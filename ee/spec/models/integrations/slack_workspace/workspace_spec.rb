# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Integrations::SlackWorkspace::Workspace, feature_category: :integrations do
  subject(:workspace) { build(:slack_workspace) }

  describe 'associations' do
    it { is_expected.to belong_to(:duo_namespace).class_name('Namespace').required }
  end

  describe 'validations' do
    it { is_expected.to validate_presence_of(:team_id) }
    it { is_expected.to validate_length_of(:team_id).is_at_most(255) }

    it 'allows one row per Slack workspace' do
      create(:slack_workspace, team_id: 'T_ACME')

      expect(build(:slack_workspace, team_id: 'T_ACME')).not_to be_valid
    end

    it 'needs a top-level group' do
      expect(build(:slack_workspace, duo_namespace: create(:group, parent: create(:group)))).not_to be_valid
      expect(build(:slack_workspace, duo_namespace: create(:user).namespace)).not_to be_valid
    end
  end

  describe 'duo_namespace_id' do
    it 'cannot be changed once created' do
      workspace = create(:slack_workspace)
      original_namespace_id = workspace.duo_namespace_id

      workspace.update!(duo_namespace: create(:group))

      expect(workspace.reload.duo_namespace_id).to eq(original_namespace_id)
    end
  end

  describe '.for_team' do
    it 'finds the workspace, and nothing for a blank team ID' do
      workspace = create(:slack_workspace, team_id: 'T_ACME')

      expect(described_class.for_team('T_ACME')).to eq(workspace)
      expect(described_class.for_team(nil)).to be_nil
    end
  end

  describe '.for_teams' do
    it 'finds the workspaces of the team IDs' do
      acme = create(:slack_workspace, team_id: 'T_ACME')
      create(:slack_workspace, team_id: 'T_OTHER')

      expect(described_class.for_teams(%w[T_ACME T_NONE])).to contain_exactly(acme)
    end
  end

  describe '.duo_group_feature_enabled?' do
    let_it_be(:root_group) { create(:group) }
    let_it_be(:subgroup) { create(:group, parent: root_group) }
    let_it_be(:other_group) { create(:group) }

    before do
      stub_feature_flags(slack_duo_group: root_group)
    end

    it 'follows the flag of the top-level group' do
      expect(described_class.duo_group_feature_enabled?(root_group)).to be(true)
      expect(described_class.duo_group_feature_enabled?(subgroup)).to be(true)
      expect(described_class.duo_group_feature_enabled?(other_group)).to be(false)
    end

    it 'follows the instance without a group' do
      expect(described_class.duo_group_feature_enabled?(nil)).to be(false)

      stub_feature_flags(slack_duo_group: true)

      expect(described_class.duo_group_feature_enabled?(nil)).to be(true)
    end
  end

  it 'is deleted with its group' do
    workspace = create(:slack_workspace)

    workspace.duo_namespace.destroy!

    expect(described_class.exists?(workspace.id)).to be(false)
  end
end
