# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Search::GlobalService, '#visibility', feature_category: :global_search do
  include SearchResultHelpers
  include ProjectHelpers

  before do
    stub_ee_application_setting(elasticsearch_search: true, elasticsearch_indexing: true)
  end

  describe 'work_items scope visibility for project-level work items', :elastic_delete_by_query do
    include_context 'ProjectPolicyTable context'

    let_it_be_with_reload(:group) { create(:group) }
    let_it_be(:shared_with_group) { create(:group) }
    let_it_be_with_reload(:project) { create(:project, namespace: group) }
    let(:projects) { [project] }

    let_it_be(:work_item) { create(:work_item, project: project) }

    let(:scope) { 'work_items' }
    let(:search) { work_item.title }

    include_context 'with search visibility users'

    where(:project_level, :feature_access_level, :access_cases) do
      access_cases_by_setting(permission_table_for_guest_feature_access)
    end

    with_them do
      before do
        Elastic::ProcessInitialBookkeepingService.track!(work_item)
      end

      it_behaves_like 'search respects visibility'
    end
  end

  def params
    { search: search, scope: scope }
  end
end
