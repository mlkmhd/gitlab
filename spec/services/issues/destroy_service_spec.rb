# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Issues::DestroyService, feature_category: :team_planning do
  let_it_be(:user, freeze: false) { create(:user) }
  let_it_be(:group, freeze: false) { create(:group, :public) }
  let_it_be(:project, freeze: false) { create(:project, :public, group: group) }

  subject(:service) { described_class.new(container: project, current_user: user) }

  context 'when issuable is an issue' do
    let!(:issue) { create(:issue, project: project, author: user, assignees: [user]) }

    it 'destroys the issue' do
      expect { service.execute(issue) }.to change { project.issues.count }.by(-1)
    end

    it 'publishes WorkItems::WorkItemDeletedEvent' do
      expect { service.execute(issue) }
        .to publish_event(::WorkItems::WorkItemDeletedEvent).with({
          id: issue.id,
          namespace_id: issue.namespace_id
        })
    end

    it 'triggers the work_item_deleted GraphQL subscription' do
      expect(GraphqlTriggers).to receive(:work_item_deleted).with(issue)

      service.execute(issue)
    end

    it 'updates open issues count cache' do
      expect_next_instance_of(Projects::OpenIssuesCountService) do |instance|
        expect(instance).to receive(:delete_cache)
      end

      service.execute(issue)
    end

    it 'invalidates the issues count cache for the assignees' do
      expect(user).to receive(:invalidate_cache_counts).once
      service.execute(issue)
    end

    it_behaves_like 'service deleting todos' do
      let(:issuable) { issue }
    end

    it_behaves_like 'service deleting label links' do
      let(:issuable) { issue }
    end

    context 'when the issue is in a milestone', :use_clean_rails_memory_store_caching do
      let(:milestone) { create(:milestone, project: project) }
      let!(:issue) { create(:issue, :closed, project: project, milestone: milestone) }

      before do
        create(:issue, project: project, milestone: milestone)
      end

      it 'refreshes the issue counts of the milestone', :aggregate_failures do
        expect(Milestones::IssuesCountService.new(milestone).count).to eq(2)
        expect(Milestones::ClosedIssuesCountService.new(milestone).count).to eq(1)

        service.execute(issue.reload)

        expect(Milestones::IssuesCountService.new(milestone).count).to eq(1)
        expect(Milestones::ClosedIssuesCountService.new(milestone).count).to eq(0)
      end
    end
  end

  context 'when issuable is a work item' do
    let!(:work_item_parent) { create(:work_item, project: project) }
    let!(:work_item) { create(:work_item, :task, project: project) }

    before do
      create(:parent_link, work_item: work_item, work_item_parent: work_item_parent)
    end

    it 'publishes WorkItems::WorkItemDeletedEvent with the parent id' do
      expect { service.execute(work_item) }
        .to publish_event(::WorkItems::WorkItemDeletedEvent).with({
          id: work_item.id,
          namespace_id: work_item.namespace_id,
          previous_work_item_parent_id: work_item_parent.id
        })
    end
  end
end
