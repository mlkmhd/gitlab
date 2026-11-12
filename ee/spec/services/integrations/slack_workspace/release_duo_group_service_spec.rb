# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Integrations::SlackWorkspace::ReleaseDuoGroupService, feature_category: :integrations do
  let_it_be(:group) { create(:group) }

  let(:team_id) { 'T_ACME' }
  let!(:workspace) { create(:slack_workspace, team_id: team_id, duo_namespace: group) }

  subject(:result) { described_class.for(workspace).execute }

  it 'deletes a claim that no longer holds, with a system audit event' do
    expect { result }.to change { AuditEvents::GroupAuditEvent.count }.by(1)

    expect(result.payload[:released]).to be(true)
    expect(Integrations::SlackWorkspace::Workspace.for_team(team_id)).to be_nil
    expect(AuditEvents::GroupAuditEvent.order(:id).last.details).to include(event_name: 'duo_in_slack_disabled',
      author_name: '(System)')
  end

  it 'keeps a claim that still holds' do
    create(:slack_integration, :group, group: group, team_id: team_id)

    expect { result }.not_to change { AuditEvents::GroupAuditEvent.count }
    expect(result.payload[:released]).to be(false)
    expect(Integrations::SlackWorkspace::Workspace.for_team(team_id)).to be_present
  end

  it 'keeps a claim another group made in the meantime' do
    service = described_class.for(workspace)
    other_group = create(:group)
    workspace.destroy!
    other_claim = create(:slack_workspace, team_id: team_id, duo_namespace: other_group)

    expect { expect(service.execute.payload[:released]).to be(false) }
      .not_to change { AuditEvents::GroupAuditEvent.count }
    expect(Integrations::SlackWorkspace::Workspace.for_team(team_id)).to eq(other_claim)
  end

  it 'does not audit when the claim was deleted already' do
    workspace.destroy!

    expect { result }.not_to change { AuditEvents::GroupAuditEvent.count }
    expect(result.payload[:released]).to be(false)
  end
end
