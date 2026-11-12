# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Members::UnassignIssuables::MergeRequestsService, feature_category: :user_management do
  let_it_be(:group) { create(:group, :private) }
  let_it_be(:project) { create(:project, group: group) }
  let_it_be_with_reload(:user) { create(:user, maintainer_of: group) }
  let_it_be(:requesting_user) { create(:user, maintainer_of: group) }
  let_it_be(:issue) { create(:issue, project: project, assignees: [user]) }
  let_it_be(:merge_requests) do
    [
      create(:merge_request, :simple, source_project: project, assignees: [user], title: 'First'),
      create(:merge_request, :simple, :closed, source_project: project, assignees: [user], title: 'Second')
    ].sort_by(&:id)
  end

  subject(:execute) { described_class.new(user, group, requesting_user).execute }

  it 'unassigns the user from the merge requests only', :aggregate_failures do
    expect(execute.payload).to eq(
      processed_merge_requests_count: 2, skipped_merge_requests_count: 0, still_assigned_merge_requests_count: 0
    )
    expect(user.assigned_merge_requests.count).to eq(0)
    expect(user.assigned_issues.count).to eq(1)
  end

  context 'when a merge request is stale' do
    before do
      allow_next_instance_of(MergeRequests::UpdateAssigneesService) do |instance|
        allow(instance).to receive(:execute).and_raise(ActiveRecord::StaleObjectError)
      end
    end

    it 'counts it as skipped and still assigned' do
      expect(execute.payload).to eq(
        processed_merge_requests_count: 0, skipped_merge_requests_count: 2, still_assigned_merge_requests_count: 2
      )
    end
  end

  context 'when the requesting user cannot update the merge requests' do
    subject(:execute) { described_class.new(user, group, create(:user)).execute }

    it 'counts them as processed but still assigned' do
      expect(execute.payload).to eq(
        processed_merge_requests_count: 2, skipped_merge_requests_count: 0, still_assigned_merge_requests_count: 2
      )
    end
  end
end
