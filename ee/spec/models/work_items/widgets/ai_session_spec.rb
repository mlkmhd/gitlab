# frozen_string_literal: true

require 'spec_helper'

RSpec.describe WorkItems::Widgets::AiSession, feature_category: :duo_agent_platform do
  describe '.latest_active_workflows_for' do
    let_it_be(:project) { create(:project) }
    let_it_be(:user) { create(:user, developer_of: project) }
    let_it_be(:work_item) { create(:work_item, project: project) }
    let_it_be(:other_work_item) { create(:work_item, project: project) }

    def create_workflow(*traits, work_item:, **attributes)
      create(:duo_workflows_workflow, *traits, project: project, user: user, issue_id: work_item.id, **attributes)
    end

    it 'returns nothing for work items without sessions' do
      expect(described_class.latest_active_workflows_for([work_item.id])).to eq({})
    end

    it 'returns only the newest unfinished session of each work item' do
      create_workflow(:finished, work_item: work_item)
      create_workflow(:running, work_item: work_item)
      newest = create_workflow(:input_required, work_item: work_item)
      other = create_workflow(:running, work_item: other_work_item)

      result = described_class.latest_active_workflows_for([work_item.id, other_work_item.id])

      expect(result).to eq(work_item.id => newest, other_work_item.id => other)
    end

    it 'ignores idle sessions, which the sessions list shows as completed' do
      create_workflow(:idle, work_item: work_item)

      expect(described_class.latest_active_workflows_for([work_item.id])).to eq({})
    end

    it 'ignores foundational chat agent sessions' do
      create_workflow(
        :running, work_item: work_item, workflow_definition: ::Ai::FoundationalChatAgent.workflow_definitions.first
      )

      expect(described_class.latest_active_workflows_for([work_item.id])).to eq({})
    end

    it 'loads sessions for many work items in a fixed number of queries' do
      create_workflow(:running, work_item: work_item)
      create_workflow(:running, work_item: other_work_item)

      control = ActiveRecord::QueryRecorder.new { described_class.latest_active_workflows_for([work_item.id]) }

      expect { described_class.latest_active_workflows_for([work_item.id, other_work_item.id]) }
        .not_to exceed_query_limit(control)
    end
  end
end
