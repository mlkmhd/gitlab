# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'User comments on a wiki page', :js, feature_category: :wiki do
  let_it_be(:user) { create(:user) }
  let(:project) { create(:project, :wiki_repo, maintainers: user) }
  let(:wiki_page) { create(:wiki_page, wiki: project.wiki, content: 'Home page') }

  before do
    sign_in(user)
    visit project_wiki_path(project, wiki_page)
  end

  def post_comment(text)
    within_testid('wiki-note-comment-form-container') do
      find_by_testid('note-textarea').fill_in(with: text)
      click_button 'Comment'
    end
  end

  it 'adds each posted comment to the list' do
    post_comment('Comment 1')

    within('#notes-list') do
      expect(page).to have_text('Comment 1')
    end
    expect(page).to have_no_testid('wiki-placeholder-note-container')

    post_comment('Comment 2')

    within('#notes-list') do
      expect(page).to have_text('Comment 1')
      expect(page).to have_text('Comment 2')
    end
  end
end
