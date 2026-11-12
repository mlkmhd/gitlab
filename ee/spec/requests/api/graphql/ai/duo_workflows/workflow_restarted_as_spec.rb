# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'Querying restartedAs on Duo Agent Platform sessions', feature_category: :duo_agent_platform do
  include GraphqlHelpers

  let_it_be(:project) { create(:project) }
  let_it_be(:user) { create(:user, developer_of: project) }
  let_it_be(:restarted_workflow) { create(:duo_workflows_workflow, project: project, user: user) }
  let_it_be(:older_restart) { create(:duo_workflows_workflow, project: project, user: user) }
  let_it_be(:newest_restart) { create(:duo_workflows_workflow, project: project, user: user) }

  let(:current_user) { user }
  let(:query) do
    graphql_query_for(:duo_workflow_workflows, { project_path: project.full_path },
      'nodes { id restartedAs { id } }')
  end

  def restart_link(workflow:, linked_workflow:)
    create(:duo_workflows_workflow_workflow, workflow: workflow, linked_workflow: linked_workflow)
  end

  def restarted_as_by_id
    graphql_data_at(:duo_workflow_workflows, :nodes).to_h do |node|
      [node['id'], node.dig('restartedAs', 'id')]
    end
  end

  before_all do
    restart_link(workflow: older_restart, linked_workflow: restarted_workflow)
    restart_link(workflow: newest_restart, linked_workflow: restarted_workflow)
  end

  before do
    stub_licensed_features(ai_workflows: true)
    allow(::Gitlab::Llm::StageCheck).to receive(:available?).with(project, :duo_workflow).and_return(true)
    allow_next_found_instance_of(User) do |found_user|
      allow(found_user).to receive(:allowed_to_use?).and_return(true)
    end
  end

  it 'returns the newest restart of a restarted session and null for the others', :aggregate_failures do
    post_graphql(query, current_user: current_user)

    expect(graphql_errors).to be_nil
    expect(restarted_as_by_id).to eq(
      restarted_workflow.to_global_id.to_s => newest_restart.to_global_id.to_s,
      older_restart.to_global_id.to_s => nil,
      newest_restart.to_global_id.to_s => nil
    )
  end

  context 'when the user cannot read the newest restart' do
    let_it_be(:other_user) { create(:user, developer_of: project) }
    let_it_be(:other_restart) { create(:duo_workflows_workflow, project: project, user: other_user) }

    before_all do
      restart_link(workflow: other_restart, linked_workflow: restarted_workflow)
    end

    it 'returns null for the restarted session' do
      post_graphql(query, current_user: current_user)

      expect(graphql_errors).to be_nil
      expect(restarted_as_by_id[restarted_workflow.to_global_id.to_s]).to be_nil
    end
  end

  describe 'query count' do
    def query_for(workflows)
      graphql_query_for(:duo_workflow_workflows, { ids: workflows.map { |w| w.to_global_id.to_s } },
        'nodes { id restartedAs { id webPath } }')
    end

    context 'when the restarts are not on the page' do
      let_it_be(:other_projects) { create_list(:project, 3, developers: user) }
      let_it_be(:restarted_in_other_projects) do
        other_projects.map do |other_project|
          create(:duo_workflows_workflow, project: other_project, user: user).tap do |workflow|
            restart_link(workflow: create(:duo_workflows_workflow, project: other_project, user: user),
              linked_workflow: workflow)
          end
        end
      end

      before do
        other_projects.each do |other_project|
          allow(::Gitlab::Llm::StageCheck).to receive(:available?).with(other_project, :duo_workflow).and_return(true)
        end
      end

      it 'does not N+1', :aggregate_failures do
        control_workflows = [restarted_workflow, restarted_in_other_projects.first]
        post_graphql(query_for(control_workflows), current_user: current_user)
        control = ActiveRecord::QueryRecorder.new do
          post_graphql(query_for(control_workflows), current_user: current_user)
        end
        expect(graphql_errors).to be_nil

        measured_query = query_for([restarted_workflow, *restarted_in_other_projects])

        expect { post_graphql(measured_query, current_user: current_user) }.not_to exceed_query_limit(control)
        expect(restarted_as_by_id.values.compact.size).to eq(4)
        expect(restarted_as_by_id.keys).not_to include(newest_restart.to_global_id.to_s)
      end
    end
  end
end
