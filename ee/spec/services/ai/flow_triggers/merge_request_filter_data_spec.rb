# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Ai::FlowTriggers::MergeRequestFilterData, feature_category: :dap_triggers do
  using RSpec::Parameterized::TableSyntax

  let_it_be(:project) { create(:project) }
  let_it_be(:human_merge_request) { create(:merge_request, source_project: project, source_branch: 'human') }
  let_it_be(:flow_draft_merge_request) do
    create(:merge_request, :draft_merge_request, source_project: project, source_branch: 'flow-draft')
  end

  before_all do
    create(:duo_workflows_workflow_merge_request,
      workflow: create(:duo_workflows_workflow, project: project),
      merge_request: flow_draft_merge_request, project: project, link_type: :created)
    # A source link is not a creator.
    create(:duo_workflows_workflow_merge_request,
      workflow: create(:duo_workflows_workflow, project: project),
      merge_request: human_merge_request, project: project, link_type: :source)
  end

  describe '.for' do
    where(:merge_request, :created_by_flow, :draft) do
      ref(:human_merge_request)      | false | false
      ref(:flow_draft_merge_request) | true  | true
    end

    with_them do
      it 'gives a value for each field of Ai::FlowTrigger::MERGE_REQUEST_FILTER_FIELDS', :aggregate_failures do
        data = described_class.for(merge_request)

        expect(data.keys).to match_array(Ai::FlowTrigger::MERGE_REQUEST_FILTER_FIELDS.keys)
        expect(data).to eq('created_by_flow' => created_by_flow, 'draft' => draft)
      end
    end
  end
end
