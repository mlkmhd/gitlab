# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Ai::Catalog::Tracking::WorkflowItemsResolutionRecorder, feature_category: :ai_catalog_curation do
  let_it_be(:project) { create(:project) }
  let_it_be(:user) { create(:user, developer_of: project) }
  let_it_be_with_reload(:flow) { create(:ai_catalog_flow, :public, project: project, name: 'Reviewer flow') }
  let_it_be(:item_version) { create(:ai_catalog_flow_version, :released, item: flow, version: '1.0.0') }

  let(:identity) do
    { item_type: 'custom_flow', item_version: item_version.version, item_schema_version: item_version.def_version,
      custom_item_id: flow.id }
  end

  let(:workflow) do
    build_stubbed(:duo_workflows_workflow, user: user, project: project, ai_catalog_item_version: item_version)
  end

  let(:served) do
    { item_type: 'agent', item_id: '7', version: '2.0.0', name: 'Served', definition_kind: 'inline', definition: {} }
  end

  let(:refused) do
    { item_type: 'agent', item_id: '8', version: '2.0.0', name: 'Refused',
      error: { code: :location, message: 'nope' } }
  end

  subject(:record) do
    described_class.new(workflow: workflow, current_user: user, root_item: root_item).execute
  end

  def root_item_with(sub_items:, reason: nil)
    { item_type: 'flow', item_id: flow.id.to_s, sub_items: sub_items, sub_items_skipped_reason: reason }
  end

  context 'when every sub-agent is served' do
    let(:root_item) { root_item_with(sub_items: [served, served.merge(item_id: '9')]) }

    it 'tracks a served resolution and audits nothing' do
      expect(::Gitlab::Audit::Auditor).not_to receive(:audit)

      expect { record }
        .to trigger_internal_events('resolve_ai_catalog_flow_sub_items')
        .with(
          user: user,
          project: project,
          additional_properties: { label: 'served', value: 2, refused_count: 0, **identity }
        )
    end
  end

  context 'when every sub-agent is refused' do
    let(:root_item) { root_item_with(sub_items: [refused, refused.merge(item_id: '9')]) }

    it 'tracks a refused resolution' do
      allow(::Gitlab::Audit::Auditor).to receive(:audit)

      expect { record }
        .to trigger_internal_events('resolve_ai_catalog_flow_sub_items')
        .with(
          user: user,
          project: project,
          additional_properties: { label: 'refused', value: 0, refused_count: 2, **identity }
        )
    end
  end

  context 'when a setting skipped the sub-agents' do
    let(:root_item) { root_item_with(sub_items: [], reason: 'beta_features_disabled') }

    it 'tracks a skipped resolution with the reason and audits nothing' do
      expect(::Gitlab::Audit::Auditor).not_to receive(:audit)

      expect { record }
        .to trigger_internal_events('resolve_ai_catalog_flow_sub_items')
        .with(
          user: user,
          project: project,
          additional_properties: {
            label: 'skipped', property: 'beta_features_disabled', value: 0, refused_count: 0, **identity
          }
        )
    end
  end

  context 'when a sub-agent is refused' do
    let(:root_item) { root_item_with(sub_items: [served, refused]) }

    it 'labels the resolution refused and counts the refusal' do
      allow(::Gitlab::Audit::Auditor).to receive(:audit)

      expect { record }
        .to trigger_internal_events('resolve_ai_catalog_flow_sub_items')
        .with(
          user: user,
          project: project,
          additional_properties: { label: 'refused', value: 1, refused_count: 1, **identity }
        )
    end

    it 'audits the refused agent and not the served one' do
      expect(::Gitlab::Audit::Auditor).to receive(:audit).once.with(
        hash_including(
          name: 'ai_catalog_flow_sub_agent_refused',
          author: user,
          scope: project,
          target: workflow,
          message: 'AI Catalog sub-agent 8 (version 2.0.0) was refused for this session',
          additional_details: { item_id: '8', version: '2.0.0', code: :location }
        )
      )

      record
    end

    context 'when the refused agent has no version' do
      let(:refused) do
        { item_type: 'agent', item_id: '47', name: 'Refused', version: nil,
          error: { code: :unknown_item, message: 'nope' } }
      end

      it 'audits the agent by id alone, without its name' do
        expect(::Gitlab::Audit::Auditor).to receive(:audit).once.with(
          hash_including(
            name: 'ai_catalog_flow_sub_agent_refused',
            message: 'AI Catalog sub-agent 47 was refused for this session',
            additional_details: { item_id: '47', version: nil, code: :unknown_item }
          )
        )

        record
      end
    end

    context 'when audit events are licensed' do
      let(:workflow) do
        create(:duo_workflows_workflow, user: user, project: project, ai_catalog_item_version: item_version)
      end

      before do
        stub_licensed_features(audit_events: true)
      end

      it 'persists a project audit event for the refused agent' do
        expect { record }.to change { AuditEvents::ProjectAuditEvent.count }.by(1)

        event = AuditEvents::ProjectAuditEvent.last

        expect(event.event_name).to eq('ai_catalog_flow_sub_agent_refused')
        expect(event.project_id).to eq(project.id)
        expect(event.target_id).to eq(workflow.id)
      end
    end
  end
end
