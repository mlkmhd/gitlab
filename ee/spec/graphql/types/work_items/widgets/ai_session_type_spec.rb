# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Types::WorkItems::Widgets::AiSessionType, feature_category: :duo_agent_platform do
  include GraphqlHelpers

  let(:fields) do
    %i[type duo_workflows can_read_duo_workflows agent_presence agent_presence_status agent_presence_human_status]
  end

  specify { expect(described_class.graphql_name).to eq('WorkItemWidgetAiSession') }

  specify { expect(described_class).to have_graphql_fields(fields) }

  it 'adds no complexity, because the signed-out work item page query is at the 200 limit' do
    expect(described_class.fields['canReadDuoWorkflows'].complexity).to eq(0)
  end

  describe 'canReadDuoWorkflows' do
    # Conditions that check duo_workflow, access_duo_agentic_chat, or read_agent_artifacts on the parent.
    let(:parent_ability_conditions) do
      %w[
        can_use_duo_workflows_in_project
        can_use_duo_workflows_in_container
        can_use_client_executed_workflow
        can_use_agentic_chat
        can_read_agent_artifacts_in_parent
      ]
    end

    it 'checks a parent ability that every rule enabling read_duo_workflow in WorkflowPolicy requires' do
      enabling_rules = ::Ai::DuoWorkflows::WorkflowPolicy.ability_map.map[:read_duo_workflow]
        .filter_map { |action, rule| rule.repr if action == :enable }

      expect(enabling_rules).to be_present
      expect(enabling_rules).to all(satisfy { |repr| repr.scan(/\w+/).intersect?(parent_ability_conditions) })
    end
  end

  describe 'agent presence fields' do
    let_it_be(:project) { create(:project) }
    let_it_be(:user) { create(:user, developer_of: project) }

    def create_work_item_with_session(trait = :running)
      create(:work_item, project: project).tap do |work_item|
        create(:duo_workflows_workflow, trait, project: project, user: user, issue_id: work_item.id)
      end
    end

    def resolve_for(work_items, field)
      batch_sync do
        work_items.map do |work_item|
          resolve_field(field, WorkItems::Widgets::AiSession.new(work_item), current_user: user)
        end
      end
    end

    it 'resolves the presence, status and human status of the active session' do
      work_item = create_work_item_with_session
      workflow = Ai::DuoWorkflows::Workflow.find_by(issue_id: work_item.id)

      expect(resolve_for([work_item], :agent_presence)).to eq([workflow])
      expect(resolve_for([work_item], :agent_presence_status))
        .to eq([Ai::DuoWorkflows::Workflow.state_machine.states[:running].value])
      expect(resolve_for([work_item], :agent_presence_human_status)).to eq(['running'])
    end

    it 'resolves nil when the work item has no active session' do
      work_item = create_work_item_with_session(:finished)

      expect(resolve_for([work_item], :agent_presence)).to eq([nil])
      expect(resolve_for([work_item], :agent_presence_status)).to eq([nil])
      expect(resolve_for([work_item], :agent_presence_human_status)).to eq([nil])
    end

    context 'with a request store', :request_store do
      it 'does not run more queries as more cards have active sessions' do
        one = [create_work_item_with_session]
        many = Array.new(5) { create_work_item_with_session }

        expect(resolve_for(many, :agent_presence)).to all(be_present)

        control = ActiveRecord::QueryRecorder.new { resolve_for(one, :agent_presence) }

        expect { resolve_for(many, :agent_presence) }.not_to exceed_query_limit(control)
      end
    end
  end
end
