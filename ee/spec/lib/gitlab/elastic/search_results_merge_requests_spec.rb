# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Gitlab::Elastic::SearchResults, 'merge_requests', feature_category: :global_search do
  let(:query) { 'hello world' }
  let_it_be(:user) { create(:user) }
  let_it_be(:project_1) { create(:project, :public, :repository, :wiki_repo) }
  let_it_be(:project_2) { create(:project, :private, :repository, :wiki_repo) }

  before do
    stub_ee_application_setting(elasticsearch_search: true, elasticsearch_indexing: true)
  end

  describe 'merge requests', :elastic_delete_by_query do
    let(:scope) { 'merge_requests' }
    let_it_be(:merge_request_1) do
      create(:merge_request, source_project: project_1, target_project: project_1,
        title: 'Hello world, here I am!', description: '20200623170000, see details in issue 287661', iid: 1)
    end

    let_it_be(:merge_request_2) do
      create(:merge_request, :conflict, source_project: project_1, target_project: project_1,
        title: 'Merge Request Two', description: 'Hello world, here I am!', iid: 2)
    end

    let_it_be(:merge_request_3) do
      create(:merge_request, source_project: project_2, target_project: project_2,
        title: 'Merge Request Three', iid: 2)
    end

    before do
      ::Elastic::ProcessInitialBookkeepingService.backfill_projects!(project_1, project_2)
      ensure_elasticsearch_index!
    end

    it_behaves_like 'a paginated object', 'merge_requests'

    it 'lists found merge requests' do
      results = described_class.new(user, query, public_and_internal_projects: false)
      merge_requests = results.objects('merge_requests')

      expect(merge_requests).to contain_exactly(merge_request_1, merge_request_2)
      expect(results.merge_requests_count).to eq 2
    end

    it_behaves_like 'can search by title for miscellaneous cases', 'merge_requests'

    context 'when description has code snippets' do
      include_context 'with code examples' do
        before do
          code_examples.values.uniq.each.with_index do |code, idx|
            sha = Digest::SHA256.hexdigest(code)
            create :merge_request, target_branch: "feature#{idx}", source_project: project_1, target_project: project_1,
              title: sha, description: code
          end

          ensure_elasticsearch_index!
        end

        it 'finds all examples' do
          code_examples.each do |query, description|
            sha = Digest::SHA256.hexdigest(description)
            merge_requests = described_class.new(user, query).objects('merge_requests')
            expect(merge_requests.map(&:title)).to include(sha)
          end
        end
      end
    end

    it 'returns empty list when merge requests are not found' do
      results = described_class.new(user, 'security')

      expect(results.objects('merge_requests')).to be_empty
      expect(results.merge_requests_count).to eq 0
    end

    it 'lists merge request when search by a valid iid' do
      results = described_class.new(user, '!2', public_and_internal_projects: false)
      merge_requests = results.objects('merge_requests')

      expect(merge_requests).to contain_exactly(merge_request_2)
      expect(results.merge_requests_count).to eq 1
    end

    it 'can also find an issue by iid without the prefixed !' do
      results = described_class.new(user, '2', public_and_internal_projects: false)
      merge_requests = results.objects('merge_requests')

      expect(merge_requests).to contain_exactly(merge_request_2)
      expect(results.merge_requests_count).to eq 1
    end

    it 'finds the MR with an out of integer range number in its description without exception' do
      results = described_class.new(user, '20200623170000', public_and_internal_projects: false)
      merge_requests = results.objects('merge_requests')

      expect(merge_requests).to contain_exactly(merge_request_1)
      expect(results.merge_requests_count).to eq 1
    end

    it 'returns empty list when search by invalid iid' do
      results = described_class.new(user, '#222')

      expect(results.objects('merge_requests')).to be_empty
      expect(results.merge_requests_count).to eq 0
    end

    describe 'merge requests with notes', :elastic_delete_by_query do
      let(:query) { 'Goodbye moon' }
      let_it_be(:merge_request) do
        create(:merge_request, source_project: project_1, source_branch: 'open-1', title: 'Hello world, here I am!')
      end

      let_it_be(:note) do
        create(:note_on_merge_request, note: 'Goodbye moon', noteable: merge_request, project: merge_request.project)
      end

      let(:results) { described_class.new(user, query, public_and_internal_projects: true) }

      before do
        Elastic::ProcessInitialBookkeepingService.track!(merge_request, note)
        ensure_elasticsearch_index!
      end

      subject(:merge_requests) { results.objects('merge_requests') }

      it 'returns the merge request when searching with note text' do
        expect(merge_requests).to contain_exactly(merge_request)
        expect(results.merge_requests_count).to eq 1
      end
    end

    describe 'filtering' do
      let_it_be(:unarchived_project) { create(:project, :public) }
      let_it_be(:archived_project) { create(:project, :public, :archived) }
      let_it_be(:opened_result) do
        create(:merge_request, :opened, source_project: project_1, source_branch: 'open-1', title: 'foo opened')
      end

      let_it_be(:closed_result) do
        create(:merge_request, :closed, source_project: project_1, source_branch: 'closed-1', title: 'foo closed')
      end

      let_it_be(:unarchived_result) do
        create(:merge_request, source_project: unarchived_project, source_branch: 'unarchived-1',
          title: 'foo unarchived')
      end

      let_it_be(:archived_result) do
        create(:merge_request, source_project: archived_project, source_branch: 'archived-1', title: 'foo archived')
      end

      let(:scope) { 'merge_requests' }
      let(:project_ids) { [project_1.id, unarchived_project.id, archived_project.id] }
      let(:results) { described_class.new(user, 'foo', filters: filters) }

      before do
        Elastic::ProcessInitialBookkeepingService.backfill_projects!(unarchived_project, archived_project)

        ensure_elasticsearch_index!
      end

      include_examples 'search results filtered by state'
      include_examples 'search results filtered by archived'
    end

    describe 'filtering by assignees and dates' do
      # freeze: false - the merge request factory mutates the assignee records
      let_it_be(:assignee, freeze: false) { create(:user) }
      let_it_be(:other_assignee, freeze: false) { create(:user) }

      let_it_be(:assigned_result) do
        create(:merge_request, source_project: project_1, target_project: project_1,
          source_branch: 'assigned-1', title: 'bar assigned', assignees: [assignee],
          created_at: 3.days.ago, updated_at: 3.days.ago)
      end

      let_it_be(:other_assigned_result) do
        create(:merge_request, source_project: project_1, target_project: project_1,
          source_branch: 'assigned-2', title: 'bar other assigned', assignees: [other_assignee],
          created_at: 10.days.ago, updated_at: 1.day.ago)
      end

      let_it_be(:unassigned_result) do
        create(:merge_request, source_project: project_1, target_project: project_1,
          source_branch: 'unassigned-1', title: 'bar unassigned',
          created_at: 10.days.ago, updated_at: 10.days.ago)
      end

      let(:scope) { 'merge_requests' }
      let(:filters) { {} }
      let(:results) { described_class.new(user, 'bar', filters: filters) }

      subject(:found) { results.objects(scope) }

      before do
        ::Elastic::ProcessInitialBookkeepingService.track!(
          assigned_result, other_assigned_result, unassigned_result
        )
        ensure_elasticsearch_index!
      end

      it 'returns every match when no filter is applied' do
        expect(found).to contain_exactly(assigned_result, other_assigned_result, unassigned_result)
      end

      context 'when filtering by assignee_ids' do
        let(:filters) { { assignee_ids: [assignee.id] } }

        it 'returns only merge requests assigned to that user' do
          expect(found).to contain_exactly(assigned_result)
        end
      end

      context 'when filtering by multiple assignee_ids' do
        let(:filters) { { assignee_ids: [assignee.id, other_assignee.id] } }

        it 'requires all of the assignees to be present' do
          expect(found).to be_empty
        end
      end

      context 'when filtering by not_assignee_ids' do
        let(:filters) { { not_assignee_ids: [assignee.id] } }

        it 'excludes merge requests assigned to that user' do
          expect(found).to contain_exactly(other_assigned_result, unassigned_result)
        end
      end

      context 'when filtering by created_after' do
        let(:filters) { { created_after: 5.days.ago } }

        it 'returns merge requests created after the given time' do
          expect(found).to contain_exactly(assigned_result)
        end
      end

      context 'when filtering by created_before' do
        let(:filters) { { created_before: 5.days.ago } }

        it 'returns merge requests created before the given time' do
          expect(found).to contain_exactly(other_assigned_result, unassigned_result)
        end
      end

      context 'when filtering by a created_at range' do
        let(:filters) { { created_after: 5.days.ago, created_before: 1.day.ago } }

        it 'returns merge requests created inside the range' do
          expect(found).to contain_exactly(assigned_result)
        end
      end

      context 'when filtering by updated_after' do
        let(:filters) { { updated_after: 5.days.ago } }

        it 'returns merge requests updated after the given time' do
          expect(found).to contain_exactly(assigned_result, other_assigned_result)
        end
      end

      context 'when filtering by updated_before' do
        let(:filters) { { updated_before: 5.days.ago } }

        it 'returns merge requests updated before the given time' do
          expect(found).to contain_exactly(unassigned_result)
        end
      end

      context 'when filtering by an updated_at range' do
        let(:filters) { { updated_after: 5.days.ago, updated_before: 2.days.ago } }

        it 'returns merge requests updated inside the range' do
          expect(found).to contain_exactly(assigned_result)
        end
      end

      describe 'the PostgreSQL search path' do
        let(:basic_results) do
          ::Gitlab::SearchResults.new(user, 'bar', Project.id_in([project_1.id]), filters: filters)
        end

        shared_examples 'identical results from both search paths' do
          it 'returns the same merge requests from Advanced Search and PostgreSQL' do
            expect(found).to match_array(basic_results.objects(scope))
          end
        end

        shared_examples 'a filter Advanced Search applies and PostgreSQL ignores' do
          it 'returns every match on the PostgreSQL path' do
            expect(basic_results.objects(scope))
              .to match_array([assigned_result, other_assigned_result, unassigned_result])
            expect(found).not_to match_array(basic_results.objects(scope))
          end
        end

        context 'when filtering by a created_at range' do
          let(:filters) { { created_after: 5.days.ago, created_before: 1.day.ago } }

          it_behaves_like 'identical results from both search paths'
        end

        context 'when filtering by assignee_ids' do
          let(:filters) { { assignee_ids: [assignee.id] } }

          it_behaves_like 'a filter Advanced Search applies and PostgreSQL ignores'
        end

        context 'when filtering by not_assignee_ids' do
          let(:filters) { { not_assignee_ids: [assignee.id] } }

          it_behaves_like 'a filter Advanced Search applies and PostgreSQL ignores'
        end

        context 'when filtering by an updated_at range' do
          let(:filters) { { updated_after: 5.days.ago, updated_before: 2.days.ago } }

          it_behaves_like 'a filter Advanced Search applies and PostgreSQL ignores'
        end
      end
    end

    describe 'ordering' do
      let_it_be(:old_result) do
        create(:merge_request, :opened, source_project: project_1, source_branch: 'old-1', title: 'sorted old',
          created_at: 1.month.ago)
      end

      let_it_be(:new_result) do
        create(:merge_request, :opened, source_project: project_1, source_branch: 'new-1', title: 'sorted recent',
          created_at: 1.day.ago)
      end

      let_it_be(:very_old_result) do
        create(:merge_request, :opened, source_project: project_1, source_branch: 'very-old-1',
          title: 'sorted very old', created_at: 1.year.ago)
      end

      let_it_be(:old_updated) do
        create(:merge_request, :opened, source_project: project_1, source_branch: 'updated-old-1', title: 'updated old',
          updated_at: 1.month.ago)
      end

      let_it_be(:new_updated) do
        create(:merge_request, :opened, source_project: project_1, source_branch: 'updated-new-1',
          title: 'updated recent', updated_at: 1.day.ago)
      end

      let_it_be(:very_old_updated) do
        create(:merge_request, :opened, source_project: project_1, source_branch: 'updated-very-old-1',
          title: 'updated very old', updated_at: 1.year.ago)
      end

      before do
        Elastic::ProcessInitialBookkeepingService.backfill_projects!(project_1)

        ensure_elasticsearch_index!
      end

      include_examples 'search results sorted' do
        let(:results_created) { described_class.new(user, 'sorted', sort: sort) }
        let(:results_updated) { described_class.new(user, 'updated', sort: sort) }
      end
    end
  end
end
