# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'Resolve the workplan questions of a work item', feature_category: :duo_agent_platform do
  include GraphqlHelpers

  let_it_be(:group) { create(:group) }
  let_it_be(:project) { create(:project, group: group) }
  let_it_be(:service_account) { create(:user, :service_account) }
  let_it_be(:developer) { create(:user, developer_of: project) }
  let_it_be(:work_item) { create(:work_item, project: project) }
  let_it_be(:workflow) do
    create(:duo_workflows_workflow, :input_required, work_item: work_item, project: project,
      workflow_definition: 'workplan/v1')
  end

  let_it_be(:note) do
    create(:note_on_work_item, noteable: work_item, project: project, author: service_account).tap do |flow_note|
      create(:duo_workflows_workflow_note, workflow: workflow, note: flow_note)
    end
  end

  let(:current_user) { developer }
  let(:input) { { 'id' => work_item.to_global_id.to_s } }
  let(:mutation) { graphql_mutation(:workItemResolveWorkplanQuestions, input, 'workItem { id } errors') }
  let(:mutation_response) { graphql_mutation_response(:work_item_resolve_workplan_questions) }

  it 'resolves the questions', :aggregate_failures do
    post_graphql_mutation(mutation, current_user: current_user)

    expect(response).to have_gitlab_http_status(:success)
    expect(mutation_response['errors']).to be_empty
    expect(mutation_response['workItem']['id']).to eq(work_item.to_global_id.to_s)
    expect(Note.find(note.id)).to be_resolved
  end

  context 'when the workplan feature flag is disabled' do
    before do
      stub_feature_flags(workplan: false)
    end

    it 'returns an error and leaves the questions open', :aggregate_failures do
      post_graphql_mutation(mutation, current_user: current_user)

      expect(mutation_response['errors']).to contain_exactly(
        Ai::DuoWorkflows::ResolveWorkplanQuestionsService::FEATURE_DISABLED_ERROR
      )
      expect(mutation_response['workItem']).to be_nil
      expect(Note.find(note.id)).not_to be_resolved
    end
  end

  context 'when the user cannot update the work item' do
    let(:current_user) { create(:user) }

    it 'returns a resource-not-available error' do
      post_graphql_mutation(mutation, current_user: current_user)

      expect(graphql_errors).to include(
        a_hash_including('message' => a_string_including("does not exist or you don't have permission"))
      )
    end
  end

  it_behaves_like 'authorizing granular token permissions for GraphQL', :update_work_item do
    let(:user) { developer }
    let(:boundary_object) { project }
    let(:mutation) { graphql_mutation(:workItemResolveWorkplanQuestions, input, 'errors') }
    let(:request) { post_graphql_mutation(mutation, token: { personal_access_token: pat }) }
  end
end
