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

    context 'for notes' do
      let(:scope) { 'notes' }
      let(:search) { note.note }

      context 'on commits' do
        let_it_be_with_reload(:group) { create(:group) }
        let_it_be_with_reload(:shared_with_group) { create(:group) }
        let_it_be_with_reload(:project) { create(:project, :repository, group: group) }
        let(:projects) { [project] }
        let(:search_level) { project }

        let!(:note) { create :note_on_commit, project: project }

        include_context 'with search visibility users'

        where(:project_level, :feature_access_level, :access_cases) do
          access_cases_by_setting(permission_table_for_repository_access)
        end

        with_them do
          before do
            project.repository.index_commits_and_blobs
          end

          it_behaves_like 'search respects visibility'
        end
      end
    end
  end
end
