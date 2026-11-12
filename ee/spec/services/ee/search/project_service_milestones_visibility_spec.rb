# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Search::ProjectService, '#visibility', feature_category: :global_search do
  include SearchResultHelpers
  include ProjectHelpers

  describe 'visibility', :elastic_delete_by_query, :sidekiq_inline do
    include_context 'ProjectPolicyTable context'

    before do
      stub_ee_application_setting(elasticsearch_search: true, elasticsearch_indexing: true)
    end

    context 'for milestones' do
      let(:scope) { 'milestones' }
      let(:search) { milestone.title }

      let_it_be_with_reload(:group) { create(:group) }
      let_it_be_with_reload(:shared_with_group) { create(:group) }
      let_it_be_with_reload(:project) { create(:project, group: group) }
      let(:projects) { [project] }
      let(:search_level) { project }

      let_it_be_with_reload(:milestone) { create :milestone, project: project }

      include_context 'with search visibility users'

      where(:project_level, :issues_access_level, :merge_requests_access_level, :access_cases) do
        access_cases_by_setting(permission_table_for_milestone_access)
      end

      with_them do
        before do
          project.update!(
            visibility_level: Gitlab::VisibilityLevel.level_value(project_level.to_s),
            issues_access_level: issues_access_level,
            merge_requests_access_level: merge_requests_access_level
          )

          Elastic::ProcessInitialBookkeepingService.track!(milestone)
        end

        it_behaves_like 'search respects visibility', project_feature_setup: false
      end
    end
  end
end
