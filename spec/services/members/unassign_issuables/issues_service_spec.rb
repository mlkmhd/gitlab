# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Members::UnassignIssuables::IssuesService, feature_category: :user_management do
  let_it_be(:group) { create(:group, :private) }
  let_it_be(:project) { create(:project, group: group) }
  let_it_be_with_reload(:user) { create(:user, maintainer_of: group) }
  let_it_be(:requesting_user) { create(:user, maintainer_of: group) }
  let_it_be(:issues) { create_list(:issue, 2, project: project, assignees: [user]).sort_by(&:id) }
  let_it_be(:merge_request) { create(:merge_request, :simple, source_project: project, assignees: [user]) }

  subject(:execute) { described_class.new(user, group, requesting_user).execute }

  it 'unassigns the user from the issues only', :aggregate_failures do
    expect(execute.payload).to eq(processed_issues_count: 2, skipped_issues_count: 0, still_assigned_issues_count: 0)
    expect(user.assigned_issues.count).to eq(0)
    expect(user.assigned_merge_requests.count).to eq(1)
  end

  context 'when an issue is stale' do
    before do
      allow_next_instance_of(Issues::UpdateService) do |instance|
        allow(instance).to receive(:execute).and_raise(ActiveRecord::StaleObjectError)
      end
    end

    it 'counts it as skipped and still assigned' do
      expect(execute.payload).to eq(processed_issues_count: 0, skipped_issues_count: 2, still_assigned_issues_count: 2)
    end
  end

  context 'when an issue can no longer be loaded' do
    before do
      allow_next_instance_of(described_class) do |service|
        allow(service).to receive(:issuable_for).and_return(nil)
      end
    end

    it 'counts it as skipped and still assigned' do
      expect(execute.payload).to eq(processed_issues_count: 0, skipped_issues_count: 2, still_assigned_issues_count: 2)
    end
  end

  context 'when the requesting user cannot update the issues' do
    subject(:execute) { described_class.new(user, group, create(:user)).execute }

    it 'counts them as processed but still assigned' do
      expect(execute.payload).to eq(processed_issues_count: 2, skipped_issues_count: 0, still_assigned_issues_count: 2)
    end
  end
end
