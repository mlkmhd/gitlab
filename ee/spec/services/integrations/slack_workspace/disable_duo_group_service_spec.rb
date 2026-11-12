# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Integrations::SlackWorkspace::DisableDuoGroupService, feature_category: :integrations do
  let_it_be(:group) { create(:group) }
  let_it_be(:owner) { create(:user, owner_of: group) }
  let_it_be(:maintainer) { create(:user, maintainer_of: group) }

  let(:team_id) { 'T_ACME' }
  let(:current_user) { owner }

  subject(:result) { described_class.new(group, current_user: current_user, team_id: team_id).execute }

  def claim
    Integrations::SlackWorkspace::Workspace.for_team(team_id)
  end

  before do
    create(:slack_integration, :group, group: group, team_id: team_id)
  end

  it 'succeeds when GitLab Duo is off already' do
    expect(result).to be_success
  end

  it 'is refused for a subgroup' do
    subgroup = create(:group, parent: group)

    expect(described_class.new(subgroup, current_user: owner, team_id: team_id).execute.reason)
      .to eq(:not_top_level_group)
  end

  context 'when the workspace runs GitLab Duo in the group' do
    before do
      create(:slack_workspace, team_id: team_id, duo_namespace: group)
    end

    it 'deletes the claim and audits it' do
      expect { result }.to change { AuditEvents::GroupAuditEvent.count }.by(1)

      expect(result).to be_success
      expect(claim).to be_nil
      expect(AuditEvents::GroupAuditEvent.order(:id).last.details).to include(event_name: 'duo_in_slack_disabled',
        author_name: owner.name)
    end

    context 'as a Maintainer' do
      let(:current_user) { maintainer }

      it 'is forbidden' do
        expect(result.reason).to eq(:forbidden)
        expect(claim).to be_present
      end
    end

    context 'when the claim no longer holds because the app was removed from the group' do
      before do
        SlackIntegration.by_team(team_id).delete_all
      end

      it 'still lets an Owner delete it' do
        expect(result).to be_success
        expect(claim).to be_nil
      end

      context 'as a Maintainer' do
        let(:current_user) { maintainer }

        it 'is not connected' do
          expect(result.reason).to eq(:workspace_not_connected)
          expect(claim).to be_present
        end
      end
    end
  end

  context 'when the workspace runs GitLab Duo in another group' do
    before do
      create(:slack_workspace, team_id: team_id, duo_namespace: create(:group))
    end

    it 'is refused' do
      expect(result.reason).to eq(:claimed_by_another_group)
      expect(claim).to be_present
    end
  end

  context 'for a workspace not installed in the group' do
    let(:team_id) { 'T_ELSEWHERE' }

    before do
      other_group = create(:group)
      create(:slack_integration, :group, group: other_group, team_id: team_id)
      create(:slack_workspace, team_id: team_id, duo_namespace: other_group)
    end

    it "says only that it isn't connected, not where it runs" do
      owned_group = create(:group).tap { |new_group| new_group.add_owner(owner) }

      expect(described_class.new(owned_group, current_user: owner, team_id: team_id)
        .execute.reason).to eq(:workspace_not_connected)
      expect(claim).to be_present
    end
  end
end
