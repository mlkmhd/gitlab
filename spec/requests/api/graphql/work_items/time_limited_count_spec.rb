# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'WorkItemConnection.timeLimitedCount', feature_category: :team_planning do
  include GraphqlHelpers

  let_it_be(:group) { create(:group) }
  let_it_be(:project) { create(:project, group: group) }
  let_it_be(:user) { create(:user, developer_of: group) }
  let_it_be(:work_items) { create_list(:work_item, 3, project: project) }

  let(:count_args) { '(limit: 1)' }
  let(:query) do
    <<~GQL
    query($path: ID!) {
      namespace(fullPath: $path) {
        workItems(includeDescendants: true) { timeLimitedCount#{count_args} }
      }
    }
    GQL
  end

  let(:variables) { { path: group.full_path } }
  let(:count_path) { %i[namespace work_items time_limited_count] }
  let(:time_limited_count) { graphql_data_at(*count_path) }

  def run_query
    post_graphql(query, current_user: user, variables: variables)
  end

  it 'returns the limited count within the fast read statement timeout' do
    expect(ApplicationRecord).to receive(:with_fast_read_statement_timeout).and_call_original

    run_query

    expect(time_limited_count).to eq(2)
  end

  context 'without a limit' do
    let(:count_args) { '' }

    it 'returns the exact count' do
      run_query

      expect(time_limited_count).to eq(3)
    end
  end

  context 'when the count exceeds the time limit' do
    let(:log_fields) { { Labkit::Fields::GL_NAMESPACE_ID => group.id } }

    before do
      allow(ApplicationRecord).to receive(:with_fast_read_statement_timeout).and_raise(ActiveRecord::QueryCanceled)
    end

    shared_examples 'a timed out count' do
      it 'returns null and logs the timeout with the parent', :aggregate_failures do
        expect(Gitlab::ErrorTracking).to receive(:log_exception).with(
          an_instance_of(ActiveRecord::QueryCanceled),
          { Labkit::Fields::ADDITIONAL_DETAILS => 'work_item_connection_time_limited_count' }.merge(log_fields)
        )

        run_query

        expect(graphql_errors).to be_nil
        expect(time_limited_count).to be_nil
      end
    end

    it_behaves_like 'a timed out count'

    context 'when the parent is a project' do
      let(:query) do
        <<~GQL
        query($path: ID!) {
          project(fullPath: $path) { workItems { timeLimitedCount(limit: 1) } }
        }
        GQL
      end

      let(:variables) { { path: project.full_path } }
      let(:count_path) { %i[project work_items time_limited_count] }
      let(:log_fields) { { Labkit::Fields::GL_PROJECT_ID => project.id } }

      it_behaves_like 'a timed out count'
    end

    context 'when the parent is not a namespace or a project' do
      let_it_be(:child) { create(:work_item, :task, project: project) }
      let_it_be(:parent_link) { create(:parent_link, work_item_parent: work_items.first, work_item: child) }

      let(:query) do
        <<~GQL
        query($id: WorkItemID!) {
          workItem(id: $id) {
            widgets { ... on WorkItemWidgetHierarchy { children { timeLimitedCount(limit: 1) } } }
          }
        }
        GQL
      end

      let(:variables) { { id: work_items.first.to_global_id.to_s } }
      let(:time_limited_count) do
        graphql_data_at(:work_item, :widgets).find { |widget| widget.key?('children') }
          .dig('children', 'timeLimitedCount')
      end

      let(:log_fields) { {} }

      it_behaves_like 'a timed out count'
    end
  end
end
