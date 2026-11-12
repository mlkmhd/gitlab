# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Ai::Catalog::FoundationalFlow::RecommendReviewers::Definition, feature_category: :code_review_workflow do
  subject(:flow) { Ai::Catalog::FoundationalFlow.recommend_reviewers_v1 }

  it 'runs on merge request events' do
    expect(flow.triggers).to contain_exactly(::Ai::FlowTrigger::EVENT_TYPES[:merge_request])
  end

  it_behaves_like 'a foundational flow precondition',
    hook_scope: :merge_request, field: 'action', allowed: %w[created], denied: %w[approved merged]

  it_behaves_like 'flow with additional context resolver',
    resolver: Ai::Catalog::FoundationalFlow::RecommendReviewers::Context

  it 'provisions triggers that run on created merge requests only' do
    expect(flow.default_trigger_filter).to eq(
      'merge_request' => { 'rules' => [{ 'field' => 'action', 'operator' => 'in', 'value' => ['created'] }] }
    )
  end

  it 'runs with no coding environment' do
    expect(Ai::Catalog::CodingEnvironment.resolve(workflow_definition: 'recommend_reviewers/v1')).to eq(:none)
  end

  context 'when recommend_reviewers_on_workhorse is disabled' do
    before do
      stub_feature_flags(recommend_reviewers_on_workhorse: false)
    end

    it 'runs with the full coding environment' do
      expect(Ai::Catalog::CodingEnvironment.resolve(workflow_definition: 'recommend_reviewers/v1')).to eq(:full)
    end
  end

  it 'accepts merge requests only' do
    expect(flow.supported_resource_types).to eq([::MergeRequest])
  end

  describe 'resolve_flow_version_for' do
    let_it_be(:project) { create(:project) }

    subject(:resolved) { flow.resolve_flow_version_for(container: project, user: nil) }

    it 'requests version 3.0.0 or later' do
      expect(resolved).to eq(
        flow_config_id: 'recommend_reviewers',
        flow_config_schema_version: 'v1',
        flow_version: '^3.0.0'
      )
    end
  end
end
