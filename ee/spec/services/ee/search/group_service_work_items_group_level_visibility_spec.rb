# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Search::GroupService, '#visibility', feature_category: :global_search do
  include SearchResultHelpers
  include ProjectHelpers

  before do
    stub_ee_application_setting(elasticsearch_search: true, elasticsearch_indexing: true)
  end

  describe 'work_items scope visibility for group-level work items (epics)', :elastic_delete_by_query,
    :sidekiq_inline do
    include_context 'ProjectPolicyTable context'
    include_context 'for GroupPolicyTable context'

    let_it_be_with_reload(:group) { create(:group) }
    let_it_be(:shared_with_group) { create(:group) }
    let_it_be_with_reload(:project) { create(:project, group: group) }
    let_it_be_with_reload(:project2) { create(:project) }

    let(:projects) { [project, project2] }
    let(:search_level) { group }

    let(:scope) { 'work_items' }
    let(:search) { 'epic work item title' }
    let_it_be(:epic_work_item) do
      create(:work_item, :group_level, :epic_with_legacy_epic, namespace: group, title: 'epic work item title')
    end

    include_context 'with search visibility users'

    where(:project_level, :access_cases) do
      access_cases_by_setting(permission_table_for_epics_access)
    end

    with_them do
      before do
        # project associated with group must have visibility_level updated to allow
        # the shared example to update the group visibility_level setting. projects cannot
        # have higher visibility than the group to which they belong
        project.update!(
          visibility_level: Gitlab::VisibilityLevel.level_value(project_level.to_s)
        )
        ::Elastic::ProcessBookkeepingService.track!(epic_work_item)
      end

      it_behaves_like 'search respects visibility', project_access: false
    end
  end

  def params
    { search: search, scope: scope }
  end
end
