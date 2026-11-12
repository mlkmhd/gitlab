# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Members::UnassignIssuablesService, feature_category: :groups_and_projects do
  let_it_be(:group) { create(:group, :private) }
  let_it_be(:project) { create(:project, group: group) }
  let_it_be_with_reload(:user) { create(:user) }
  let_it_be(:requesting_user) { create(:user) }
  let_it_be_with_reload(:assigned_issue1) { create(:issue, project: project, assignees: [user]) }
  let_it_be_with_reload(:assigned_issue2) { create(:issue, project: project, assignees: [user]) }

  let!(:assigned_merge_request1) { create(:merge_request, :simple, :closed, target_project: project, source_project: project, assignees: [user], title: 'Test1') }
  let!(:assigned_merge_request2) { create(:merge_request, :simple, :opened, target_project: project, source_project: project, assignees: [user], title: 'Test2') }

  describe '#execute' do
    shared_examples 'missing request_user raises an error' do
      context 'when requesting_user is nil' do
        let_it_be(:requesting_user) { nil }

        it 'raises ArgumentError' do
          expect { subject }.to raise_error(ArgumentError, 'requesting_user must be given')
        end
      end
    end

    shared_examples 'stale objects are ignored and skipped' do |issue_count, mr_count|
      context 'when Issues::UpdateService raises StaleObjectError' do
        before do
          allow_next_instance_of(Issues::UpdateService) do |instance|
            allow(instance).to receive(:execute).and_raise(ActiveRecord::StaleObjectError)
          end
        end

        it 'does not raise an error' do
          expect { subject }.not_to raise_error
        end

        it 'does not count the stale issues' do
          expect(subject.payload).to include(processed_issues_count: 0, processed_merge_requests_count: mr_count)
        end
      end

      context 'when MergeRequests::UpdateAssigneesService raises StaleObjectError' do
        before do
          allow_next_instance_of(MergeRequests::UpdateAssigneesService) do |instance|
            allow(instance).to receive(:execute).and_raise(ActiveRecord::StaleObjectError)
          end
        end

        it 'does not raise an error' do
          expect { subject }.not_to raise_error
        end

        it 'does not count the stale merge requests' do
          expect(subject.payload).to include(processed_issues_count: issue_count, processed_merge_requests_count: 0)
        end
      end
    end

    RSpec.shared_examples 'unassignment events' do
      # :sidekiq_inline is used b/c unlike issues, assignee changes for MRs get handled asynchronously.
      it 'records unassignment events', :sidekiq_inline, :aggregate_failures do
        expect { subject }
          .to change { Note.where('note ILIKE ?', '%unassigned%').count }.by(
            user.assigned_issues.count + user.assigned_merge_requests.count
          )
      end
    end

    RSpec.shared_examples 'un-assigning issuables' do |issue_count, mr_count, open_issue_count, open_mr_count|
      it 'removes issuable assignments', :aggregate_failures do
        expect { subject }
          .to change { user.assigned_issues.count }.from(issue_count).to(0)
          .and change { user.assigned_merge_requests.count }.from(mr_count).to(0)
      end

      it 'returns the counts for issues and merge requests', :aggregate_failures do
        expect(subject).to be_success
        expect(subject.payload).to eq(
          processed_issues_count: issue_count,
          skipped_issues_count: 0,
          still_assigned_issues_count: 0,
          processed_merge_requests_count: mr_count,
          skipped_merge_requests_count: 0,
          still_assigned_merge_requests_count: 0
        )
      end

      it 'invalidates user cache', :aggregate_failures, :clean_gitlab_redis_cache do
        expect(user.assigned_open_merge_requests_count).to eq(open_mr_count)
        expect(user.assigned_open_issues_count).to eq(open_issue_count)

        subject

        expect(user.assigned_open_merge_requests_count).to eq(0)
        expect(user.assigned_open_issues_count).to eq(0)
      end
    end

    context 'when entity is nil' do
      subject(:result) { described_class.new(user, nil, requesting_user).execute }

      it 'returns success with an empty payload and unassigns nothing', :aggregate_failures do
        expect { result }.not_to change { user.assigned_issues.count }
        expect(result).to be_success
        expect(result.payload).to eq({})
      end
    end

    context 'when a user leaves a project' do
      before do
        project.add_maintainer(requesting_user)
        project.add_maintainer(user)
      end

      subject { described_class.new(user, project, requesting_user).execute }

      it_behaves_like 'un-assigning issuables', 2, 2, 2, 1
      it_behaves_like 'unassignment events'
      it_behaves_like 'missing request_user raises an error'
      it_behaves_like 'stale objects are ignored and skipped', 2, 2

      it 'unassigns every issue past the work item update limit', :freeze_time, :clean_gitlab_redis_rate_limiting do
        stub_application_setting(work_item_update_limit: 1)

        described_class.new(user, project, requesting_user).execute

        expect(user.assigned_issues).to be_empty
      end
    end

    context 'when a user leaves a group' do
      let_it_be(:project2) { create(:project, group: group) }

      let_it_be_with_reload(:assigned_issue3) { create(:issue, project: project2, assignees: [user]) }
      let_it_be_with_reload(:assigned_issue4) { create(:issue, project: project2, assignees: [user]) }

      let!(:assigned_merge_request3) { create(:merge_request, :simple, :closed, target_project: project2, source_project: project2, assignees: [user], title: 'Test1') }
      let!(:assigned_merge_request4) { create(:merge_request, :simple, :opened, target_project: project2, source_project: project2, assignees: [user], title: 'Test2') }

      before do
        group.add_maintainer(requesting_user)
        group.add_maintainer(user)
      end

      subject { described_class.new(user, group, requesting_user).execute }

      it_behaves_like 'un-assigning issuables', 4, 4, 4, 2
      it_behaves_like 'unassignment events'
      it_behaves_like 'stale objects are ignored and skipped', 4, 4
    end
  end
end
