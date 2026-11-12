# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'Snippet elastic search', :js, :elastic_delete_by_query, :aggregate_failures,
  :with_current_organization, feature_category: :global_search do
  let_it_be(:regular_user) { create(:user) }
  let_it_be(:non_member_project) { create(:project, :public) }
  let_it_be(:member_project) { create(:project, :private, maintainers: regular_user) }

  before do
    stub_ee_application_setting(elasticsearch_search: true, elasticsearch_indexing: true)

    Sidekiq::Testing.inline! do
      create(:personal_snippet, :public, title: 'public personal snippet',
        description: 'a public personal snippet description')
      create(:personal_snippet, :private, title: 'private personal snippet',
        description: 'a private personal snippet description')
      create(:project_snippet, :public, project: non_member_project,
        title: 'non-member project snippet', description: 'a non-member project snippet description')
      create(:project_snippet, :private, project: member_project,
        title: 'member project snippet', description: 'a member project snippet description')
      create(:personal_snippet, :public, title: 'matched by file name only', description: 'no keyword here',
        file_name: 'snippet_notes.rb')

      ensure_elasticsearch_index!
    end

    sign_in(regular_user)
    visit explore_snippets_path
  end

  it 'renders indexed results through the Elasticsearch path' do
    submit_search('snippet')

    within('.results') do
      expect(page).to have_content('public personal snippet')
      expect(page).not_to have_content('private personal snippet')

      expect(page).to have_content('member project snippet')
      expect(page).to have_content('non-member project snippet')

      # Only basic search matches file names, so this keeps the example tied to the Elasticsearch path.
      expect(page).not_to have_content('matched by file name only')
    end
  end
end
