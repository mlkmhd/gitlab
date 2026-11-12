# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'Updating a work item saved view', feature_category: :planning_views do
  include GraphqlHelpers

  let_it_be(:group) { create(:group) }
  let_it_be(:current_user) { create(:user, developer_of: group) }
  let_it_be_with_reload(:saved_view) { create(:saved_view, namespace: group, author: current_user) }

  let(:status) { WorkItems::Statuses::SystemDefined::Status.find_by_name('In progress') }
  let(:status_filter) { { id: status.to_global_id.to_s } }
  let(:mutation) do
    graphql_mutation(
      :workItemSavedViewUpdate,
      { id: saved_view.to_global_id.to_s, filters: { status: status_filter } },
      'savedView { id filters } errors'
    )
  end

  before do
    stub_licensed_features(work_item_status: true)
  end

  shared_examples 'preserves the status filter' do
    it 'stores and returns the requested status', :aggregate_failures do
      post_graphql_mutation(mutation, current_user: current_user)

      response_data = graphql_mutation_response(:work_item_saved_view_update)
      expect(graphql_errors).to be_nil
      expect(response_data['errors']).to be_empty
      expect(response_data.dig('savedView', 'filters', 'status')).to eq('name' => status.name)
      expect(saved_view.reload.filter_data['status']).to eq(
        'id' => status.id,
        'input_format' => 'id',
        'custom' => custom
      )
    end
  end

  context 'with a system-defined status ID' do
    let(:custom) { false }

    it_behaves_like 'preserves the status filter'
  end

  context 'with a custom status ID' do
    let_it_be(:status) { create(:work_item_custom_status, :in_progress, namespace: group) }
    let(:custom) { true }

    it_behaves_like 'preserves the status filter'
  end
end
