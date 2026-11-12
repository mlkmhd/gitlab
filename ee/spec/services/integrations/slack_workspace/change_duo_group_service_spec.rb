# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Integrations::SlackWorkspace::ChangeDuoGroupService, feature_category: :integrations do
  let_it_be(:organization) { create(:common_organization) }
  let_it_be(:group) { create(:group, organization: organization) }
  let_it_be(:other_group) { create(:group, organization: organization) }
  let_it_be(:admin) { create(:admin) }

  let(:team_id) { 'T_INSTANCE' }

  before_all do
    create(:slack_integration, :instance, organization: organization, team_id: 'T_INSTANCE')
  end

  def choose(to, current_user: admin)
    described_class.new(to, current_user: current_user, team_id: team_id).execute
  end

  def duo_group
    Integrations::SlackWorkspace::Workspace.for_team(team_id)&.duo_namespace
  end

  context 'as an administrator', :enable_admin_mode do
    it 'chooses a group, moves to another one, and turns GitLab Duo off, auditing each change', :aggregate_failures do
      expect { expect(choose(group)).to be_success }.to change { AuditEvents::GroupAuditEvent.count }.by(1)
      expect(duo_group).to eq(group)

      expect { expect(choose(other_group)).to be_success }.to change { AuditEvents::GroupAuditEvent.count }.by(2)
      expect(duo_group).to eq(other_group)

      expect { expect(choose(nil)).to be_success }.to change { AuditEvents::GroupAuditEvent.count }.by(1)
      expect(duo_group).to be_nil
    end

    it 'succeeds without a change when the group is the Duo group already' do
      choose(group)

      expect { expect(choose(group)).to be_success }.not_to change { AuditEvents::GroupAuditEvent.count }
    end

    it 'succeeds when GitLab Duo is off already' do
      expect(choose(nil)).to be_success
    end

    it 'keeps the old group when the new one is refused', :aggregate_failures do
      choose(group)

      expect(choose(create(:group, parent: other_group)).reason).to eq(:not_top_level_group)
      expect(duo_group).to eq(group)
    end

    it 'keeps the old group when the new one is archived, without auditing a turn-off', :aggregate_failures do
      choose(group)
      archived = create(:group, :archived, organization: organization)

      expect(Gitlab::Audit::Auditor).not_to receive(:audit)
      expect(choose(archived).reason).to eq(:inactive_group)
      expect(duo_group).to eq(group)
    end

    it 'keeps the old group when the flag is off for the new one', :aggregate_failures do
      choose(group)
      allow(Integrations::SlackWorkspace::Workspace).to receive(:duo_group_feature_enabled?).and_call_original
      allow(Integrations::SlackWorkspace::Workspace).to receive(:duo_group_feature_enabled?).with(other_group)
        .and_return(false)

      expect(Gitlab::Audit::Auditor).not_to receive(:audit)
      expect(choose(other_group).reason).to eq(:not_available)
      expect(duo_group).to eq(group)
    end

    it 'keeps the old group when it cannot be turned off', :aggregate_failures do
      choose(group)
      allow(Integrations::SlackWorkspace::Workspace).to receive(:duo_group_feature_enabled?).and_call_original
      allow(Integrations::SlackWorkspace::Workspace).to receive(:duo_group_feature_enabled?).with(group)
        .and_return(false)

      expect(choose(other_group).reason).to eq(:not_available)
      expect(duo_group).to eq(group)
    end

    it 'restores the old group when the new one fails after the old one was turned off', :aggregate_failures do
      choose(group)
      allow_next_instance_of(Integrations::SlackWorkspace::EnableDuoGroupService) do |service|
        allow(service).to receive(:execute)
          .and_return(ServiceResponse.error(message: 'lost', reason: :claimed_by_another_group))
      end

      expect(choose(other_group).reason).to eq(:claimed_by_another_group)
      expect(duo_group).to eq(group)
    end

    it 'releases a claim that no longer holds before it chooses, with a system audit event', :aggregate_failures do
      # A group of another organization can't run GitLab Duo for this organization's instance workspace.
      create(:slack_workspace, team_id: team_id, duo_namespace: create(:group, organization: create(:organization)))

      expect { expect(choose(group)).to be_success }.to change { AuditEvents::GroupAuditEvent.count }.by(2)
      expect(duo_group).to eq(group)
    end

    it 'asks for a workspace without a team ID' do
      expect(described_class.new(group, current_user: admin, team_id: nil).execute.reason).to eq(:missing_team)
    end

    it 'changes nothing for an Owner who is not an administrator', :aggregate_failures do
      choose(group)

      expect(choose(other_group, current_user: create(:user, owner_of: other_group)).reason).to eq(:forbidden)
      expect(duo_group).to eq(group)
    end

    context 'with the feature flag off for the instance' do
      before do
        stub_feature_flags(slack_duo_group: false)
      end

      it 'changes nothing', :aggregate_failures do
        expect(choose(group).reason).to eq(:not_available)
        expect(duo_group).to be_nil
      end
    end
  end

  context 'without a user' do
    it 'changes nothing', :aggregate_failures do
      expect(choose(group, current_user: nil).reason).to eq(:forbidden)
      expect(duo_group).to be_nil
    end
  end

  context 'as an administrator without admin mode' do
    it 'changes nothing', :aggregate_failures do
      expect(choose(group).reason).to eq(:forbidden)
      expect(duo_group).to be_nil
    end
  end
end
