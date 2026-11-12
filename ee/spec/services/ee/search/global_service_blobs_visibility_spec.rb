# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Search::GlobalService, '#visibility', feature_category: :global_search do
  include SearchResultHelpers
  include ProjectHelpers

  describe 'visibility', :sidekiq_inline do
    include_context 'ProjectPolicyTable context'

    let_it_be_with_reload(:group) { create(:group) }
    let_it_be_with_reload(:shared_with_group) { create(:group) }
    let_it_be_with_reload(:project) { create(:project, :repository, namespace: group) }
    let(:projects) { [project] }

    include_context 'with search visibility users'

    context 'for blobs' do
      let(:scope) { 'blobs' }
      let(:search) { '.gitmodules' }

      context 'when using advanced search', :elastic_delete_by_query do
        where(:project_level, :feature_access_level, :access_cases) do
          access_cases_by_setting(permission_table_for_repository_access)
        end

        with_them do
          before do
            stub_ee_application_setting(elasticsearch_search: true, elasticsearch_indexing: true)
            project.repository.index_commits_and_blobs
          end

          it_behaves_like 'search respects visibility'
        end
      end

      context 'when using zoekt', :zoekt_settings_enabled, :zoekt_cache_disabled do
        where(:project_level, :feature_access_level, :access_cases) do
          access_cases_by_setting(permission_table_for_repository_access)
        end

        with_them do
          before do
            zoekt_ensure_namespace_indexed!(group)
          end

          it_behaves_like 'search respects visibility'
        end
      end

      describe 'custom roles' do
        context 'when using advanced search', :elastic_delete_by_query do
          before do
            stub_ee_application_setting(elasticsearch_search: true, elasticsearch_indexing: true)
            project.repository.index_commits_and_blobs
          end

          it_behaves_like 'supports custom role access :read_code access'
        end

        context 'when using zoekt', :zoekt_settings_enabled, :zoekt_cache_disabled do
          before do
            zoekt_ensure_namespace_indexed!(group)
          end

          it_behaves_like 'supports custom role access :read_code access'
        end
      end
    end
  end
end
