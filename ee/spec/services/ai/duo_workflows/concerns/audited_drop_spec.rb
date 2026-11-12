# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Ai::DuoWorkflows::Concerns::AuditedDrop, feature_category: :duo_agent_platform do
  let(:test_class) do
    Class.new do
      include Ai::DuoWorkflows::Concerns::AuditedDrop

      public :drop_and_audit
    end
  end

  let_it_be(:project) { create(:project) }
  let_it_be(:user) { create(:user) }
  let_it_be_with_reload(:workflow) { create(:duo_workflows_workflow, :running, project: project, user: user) }

  subject(:drop_and_audit) do
    test_class.new.drop_and_audit(workflow, drop_reason: 'start_failed', author: user, message: 'Dropped')
  end

  it 'drops the workflow, then emits the event, the audit and the subscription update', :aggregate_failures do
    expect(::Gitlab::Audit::Auditor).to receive(:audit)
      .with(hash_including(name: described_class::DROP_AUDIT_EVENT_NAME, author: user, message: 'Dropped'))
    expect(GraphqlTriggers).to receive(:workflow_events_updated)

    expect { drop_and_audit }.to trigger_internal_events('agent_platform_session_dropped')

    expect(workflow.reload).to be_failed
    expect(workflow.drop_reason).to eq('start_failed')
  end

  context 'when the drop cannot be saved' do
    before do
      allow(workflow).to receive(:drop).and_return(false)
    end

    it 'emits nothing', :aggregate_failures do
      expect(::Gitlab::Audit::Auditor).not_to receive(:audit)
      expect(GraphqlTriggers).not_to receive(:workflow_events_updated)

      expect { drop_and_audit }.not_to trigger_internal_events('agent_platform_session_dropped')
    end
  end

  context 'when the audit fails' do
    let(:error) { StandardError.new('audit down') }

    before do
      allow(::Gitlab::Audit::Auditor).to receive(:audit).and_raise(error)
    end

    it 'tracks the error and still publishes the status change', :aggregate_failures do
      expect(::Gitlab::ErrorTracking).to receive(:track_exception).with(error, workflow_id: workflow.id)
      expect(GraphqlTriggers).to receive(:workflow_events_updated)

      drop_and_audit

      expect(workflow.reload).to be_failed
    end
  end

  context 'when the subscription update fails' do
    let(:error) { StandardError.new('subscription down') }

    before do
      allow(GraphqlTriggers).to receive(:workflow_events_updated).and_raise(error)
    end

    it 'tracks the error' do
      expect(::Gitlab::ErrorTracking).to receive(:track_exception).with(error, workflow_id: workflow.id)

      drop_and_audit
    end
  end
end
