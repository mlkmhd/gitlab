# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Search::ProjectService, '#visibility', feature_category: :global_search do
  include SearchResultHelpers
  include ProjectHelpers

  describe 'visibility', :sidekiq_inline, :elastic_delete_by_query do
    using RSpec::Parameterized::TableSyntax
    include_context 'ProjectPolicyTable context'

    let_it_be_with_reload(:group) { create(:group) }
    let_it_be_with_reload(:shared_with_group) { create(:group) }
    let_it_be_with_reload(:project) { create(:project, :repository, :in_group, namespace: group) }

    let(:projects) { [project] }
    let(:search_level) { project }

    include_context 'with search visibility users'

    before do
      stub_ee_application_setting(elasticsearch_search: true, elasticsearch_indexing: true)
      project.repository.index_commits_and_blobs
    end

    where(:project_level, :feature_access_level, :access_cases) do
      access_cases_by_setting(permission_table_for_repository_access)
    end

    with_them do
      context 'for commits' do
        it_behaves_like 'search respects visibility' do
          let(:scope) { 'commits' }
          let(:search) { 'initial' }
        end
      end
    end
  end
end
