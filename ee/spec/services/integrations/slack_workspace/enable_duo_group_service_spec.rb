# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Integrations::SlackWorkspace::EnableDuoGroupService, feature_category: :integrations do
  let_it_be(:organization) { create(:organization) }
  let_it_be(:group) { create(:group, organization: organization) }
  let_it_be(:project) { create(:project, group: group) }
  let_it_be(:owner) { create(:user, owner_of: group) }
  let_it_be(:maintainer) { create(:user, maintainer_of: group) }
  let_it_be(:admin) { create(:admin) }

  let(:team_id) { 'T_ACME' }
  let(:current_user) { owner }
  let(:target_group) { group }

  subject(:result) { described_class.new(target_group, current_user: current_user, team_id: team_id).execute }

  def claim
    Integrations::SlackWorkspace::Workspace.for_team(team_id)
  end

  context 'when the workspace is installed in the hierarchy' do
    before do
      create(:slack_integration, :project, project: project, team_id: team_id, team_name: 'Acme')
    end

    it 'makes the group the Duo group of the workspace and audits it' do
      expect { result }.to change { AuditEvents::GroupAuditEvent.count }.by(1)

      expect(result).to be_success
      expect(claim.duo_namespace).to eq(group)
      expect(AuditEvents::GroupAuditEvent.order(:id).last.details).to include(event_name: 'duo_in_slack_enabled',
        target_details: 'Acme (T_ACME)')
    end

    it 'is idempotent' do
      described_class.new(group, current_user: owner, team_id: team_id).execute

      expect { result }.not_to change { AuditEvents::GroupAuditEvent.count }
      expect(result).to be_success
    end

    context 'as a Maintainer' do
      let(:current_user) { maintainer }

      it 'is forbidden' do
        expect(result.reason).to eq(:forbidden)
        expect(claim).to be_nil
      end
    end

    context 'without a user' do
      let(:current_user) { nil }

      it 'is forbidden' do
        expect(result.reason).to eq(:forbidden)
        expect(claim).to be_nil
      end
    end

    context 'for a subgroup' do
      let(:target_group) { create(:group, parent: group) }

      it 'is refused' do
        expect(result.reason).to eq(:not_top_level_group)
      end
    end

    context 'when another group holds a valid claim' do
      let_it_be(:other_group) { create(:group, organization: organization) }

      before do
        create(:slack_integration, :group, group: other_group, team_id: team_id)
        create(:slack_workspace, team_id: team_id, duo_namespace: other_group)
      end

      it 'is refused and keeps the claim' do
        expect(result.reason).to eq(:claimed_by_another_group)
        expect(claim.duo_namespace).to eq(other_group)
      end
    end

    context 'when a concurrent request claims the workspace between the lookup and the insert' do
      let_it_be(:other_group) { create(:group, organization: organization) }

      # Inserts the winner's claim first. Without `raising`, the second insert fails the uniqueness validation.
      def race(winner, raising)
        allow(Integrations::SlackWorkspace::Workspace).to receive(:create!).and_wrap_original do |original, **attrs|
          original.call(team_id: team_id, duo_namespace: winner)
          raising ? raise(raising) : original.call(**attrs)
        end
      end

      where(raising: [nil, ActiveRecord::RecordNotUnique])

      with_them do
        it 'succeeds without a second audit event when the same group won', :aggregate_failures do
          race(group, raising)

          expect { result }.not_to change { AuditEvents::GroupAuditEvent.count }
          expect(result).to be_success
          expect(result.payload[:slack_workspace]).to eq(claim)
          expect(claim.duo_namespace).to eq(group)
        end

        it 'is refused when another group won', :aggregate_failures do
          race(other_group, raising)

          expect(result.reason).to eq(:claimed_by_another_group)
          expect(claim.duo_namespace).to eq(other_group)
        end
      end
    end

    it 'is refused when the winning claim is already gone' do
      allow(Integrations::SlackWorkspace::Workspace).to receive(:create!)
        .and_raise(ActiveRecord::RecordNotUnique)

      expect(result.reason).to eq(:claimed_by_another_group)
      expect(claim).to be_nil
    end

    it 'raises a validation error that is not about the team ID' do
      subgroup = create(:group, parent: group)
      allow(Integrations::SlackWorkspace::Workspace).to receive(:create!).and_wrap_original do |original, **attrs|
        original.call(**attrs, duo_namespace: subgroup)
      end

      expect { result }.to raise_error(ActiveRecord::RecordInvalid, /top-level group/)
    end

    context 'when another group holds a claim that no longer holds' do
      let_it_be(:other_group) { create(:group, organization: organization) }

      before do
        create(:slack_workspace, team_id: team_id, duo_namespace: other_group)
      end

      it 'releases the old claim with a system audit event and claims the workspace' do
        expect(result).to be_success
        expect(claim.duo_namespace).to eq(group)
        expect(AuditEvents::GroupAuditEvent.where(group_id: other_group.id).order(:id).last.details)
          .to include(event_name: 'duo_in_slack_disabled', author_name: '(System)')
      end
    end

    context 'with the feature flag off' do
      before do
        stub_feature_flags(slack_duo_group: false)
      end

      it 'is not available' do
        expect(result.reason).to eq(:not_available)
      end
    end

    context 'with the feature flag on for another top-level group only' do
      before do
        stub_feature_flags(slack_duo_group: create(:group))
      end

      it 'is not available' do
        expect(result.reason).to eq(:not_available)
      end
    end

    context 'for an archived group' do
      let(:target_group) { create(:group, organization: organization) }

      before do
        target_group.add_owner(owner)
        create(:slack_integration, :group, group: target_group, team_id: team_id)
        target_group.namespace_settings.update!(archived: true)
      end

      it 'is refused' do
        expect(result.reason).to eq(:inactive_group)
        expect(claim).to be_nil
      end
    end
  end

  context 'when the workspace is not installed in the hierarchy' do
    it 'is refused' do
      expect(result.reason).to eq(:workspace_not_connected)
    end
  end

  context 'without a team ID' do
    let(:team_id) { nil }

    it 'asks for a workspace' do
      expect(result.reason).to eq(:missing_team)
    end
  end

  context 'when the workspace is installed for the instance' do
    before do
      create(:slack_integration, :instance, organization: organization, team_id: team_id)
    end

    it 'is refused for an Owner' do
      expect(result.reason).to eq(:managed_by_admin)
    end

    it 'is refused without a user' do
      expect(described_class.new(group, current_user: nil, team_id: team_id).execute.reason)
        .to eq(:managed_by_admin)
    end

    context 'as an administrator', :enable_admin_mode do
      let(:current_user) { admin }

      it 'is refused outside the Admin area' do
        expect(result.reason).to eq(:managed_by_admin)
        expect(claim).to be_nil
      end

      it 'makes the group the Duo group of the workspace from the Admin area' do
        result = described_class.new(group, current_user: admin, team_id: team_id, admin_area: true).execute

        expect(result).to be_success
        expect(claim.duo_namespace).to eq(group)
      end
    end

    context 'in the Admin area' do
      it 'is refused for an Owner' do
        expect(described_class.new(group, current_user: owner, team_id: team_id, admin_area: true).execute.reason)
          .to eq(:managed_by_admin)
      end

      it 'is refused for an administrator without admin mode' do
        expect(described_class.new(group, current_user: admin, team_id: team_id, admin_area: true).execute.reason)
          .to eq(:managed_by_admin)
      end

      it 'is refused without a user' do
        expect(described_class.new(group, current_user: nil, team_id: team_id, admin_area: true).execute.reason)
          .to eq(:managed_by_admin)
      end
    end
  end
end
