# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Types::Ai::DuoWorkflows::WorkflowType, feature_category: :duo_agent_platform do
  include GraphqlHelpers

  it { expect(described_class).to have_graphql_field(:user) }
  it { expect(described_class).to have_graphql_field(:work_item_links) }
  it { expect(described_class).to have_graphql_field(:merge_request_links) }
  it { expect(described_class).to have_graphql_field(:note_links) }
  it { expect(described_class).to have_graphql_field(:pipeline_links) }
  it { expect(described_class).to have_graphql_field(:workflow_links) }
  it { expect(described_class).to have_graphql_field(:inverse_workflow_links) }
  it { expect(described_class).to have_graphql_field(:restarted_as) }
  it { expect(described_class).to have_graphql_field(:flow_metadata_version) }
  it { expect(described_class).to have_graphql_field(:flow_metadata_id) }
  it { expect(described_class).to have_graphql_field(:flow_metadata_schema_version) }
  it { expect(described_class).to have_graphql_field(:web_url) }
  it { expect(described_class).to have_graphql_field(:web_path) }
  it { expect(described_class).to have_graphql_field(:source_type) }
  it { expect(described_class).to have_graphql_field(:source_link) }
  it { expect(described_class).to have_graphql_field(:ai_catalog_item) }
  it { expect(described_class).to have_graphql_field(:allow_client_injected_mcp_tools) }
  it { expect(described_class).to have_graphql_field(:trigger_source) }
  it { expect(described_class).to have_graphql_field(:flow_trigger) }
  it { expect(described_class).to have_graphql_field(:file_attachments_allowed) }
  it { expect(described_class).to have_graphql_field(:tool_access_policies) }

  describe 'field scopes' do
    using RSpec::Parameterized::TableSyntax

    where(:field_name) do
      %w[archived stalled resourceIid resourceWebUrl webUrl webPath user workItem workItemLinks mergeRequestLinks
        noteLinks pipelineLinks workflowLinks inverseWorkflowLinks mergeRequest summary title aiCatalogItem
        sourceType sourceLink allowClientInjectedMcpTools triggerSource flowTrigger fileAttachmentsAllowed
        toolAccessPolicies restartedAs]
    end

    with_them do
      it "includes the correct scopes for the #{params[:field_name]} field" do
        expect(described_class.fields[field_name].instance_variable_get(:@scopes)).to include(:api, :read_api,
          :ai_features, :ai_workflows)
      end
    end
  end

  describe 'auditEvents field' do
    subject(:field) { described_class.fields['auditEvents'] }

    it { expect(described_class).to have_graphql_field(:audit_events) }

    it 'returns an AiAuditEvent connection type' do
      expect(field.type.unwrap.graphql_name).to eq('AiAuditEventConnection')
    end

    it 'requires :read_agent_artifacts authorization' do
      expect(field.instance_variable_get(:@authorize)).to contain_exactly(:read_agent_artifacts)
    end
  end

  describe '#web_path' do
    let(:workflow) { build_stubbed(:duo_workflows_workflow, project: nil, namespace: build_stubbed(:group)) }

    before do
      allow(described_class).to receive(:authorized?).and_return(true)
    end

    it 'returns the relative path of the session' do
      expect(resolve_field(:web_path, workflow))
        .to eq("/groups/#{workflow.namespace.full_path}/-/automate/agent-sessions/#{workflow.id}")
    end
  end

  describe 'checkpoint fields of a session the read gate serves from the legacy table' do
    let_it_be(:project) { create(:project) }
    # refind, not reload: the legacy reader memoizes per lineage, and a checkpoint write touches the workflow.
    let_it_be_with_refind(:workflow) { create(:duo_workflows_workflow, project: project) }
    let_it_be(:oldest) { create(:duo_workflows_checkpoint, workflow: workflow, project: project, thread_ts: 'ts-1') }
    let_it_be(:newest) { create(:duo_workflows_checkpoint, workflow: workflow, project: project, thread_ts: 'ts-2') }

    before do
      allow(described_class).to receive(:authorized?).and_return(true)
    end

    it 'loads the newest and oldest rows through the page-level primers', :aggregate_failures do
      expect(batch_sync { resolve_field(:latest_checkpoint, workflow, current_user: workflow.user) }.thread_ts)
        .to eq('ts-2')
      expect(batch_sync { resolve_field(:first_checkpoint, workflow, current_user: workflow.user) }.thread_ts)
        .to eq('ts-1')
    end
  end

  describe '#file_attachments_allowed' do
    let_it_be(:user) { create(:user) }
    let_it_be(:group) { create(:group) }
    let_it_be(:project) { create(:project, group: create(:group, parent: group)) }
    let_it_be(:workflow) { create(:duo_workflows_workflow, project: project, user: user) }

    before do
      allow(described_class).to receive(:authorized?).and_return(true)
    end

    where(:allowed) { [true, false] }

    with_them do
      it 'returns what Ai::FileAttachments decides for the top-level group and workflow user' do
        allow(::Ai::FileAttachments).to receive(:allowed?).with(group, user: user).and_return(allowed)

        expect(resolve_field(:file_attachments_allowed, workflow)).to be(allowed)
      end
    end
  end
end
