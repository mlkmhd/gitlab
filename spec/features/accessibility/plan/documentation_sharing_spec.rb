# frozen_string_literal: true

require 'spec_helper'

# Accessibility Test for Golden User Journey: Documentation Sharing

RSpec.describe 'Accessibility: Documentation Sharing', :js, feature_category: :wiki do
  include WikiHelpers

  let(:project) { create(:project, :wiki_repo) }
  let(:wiki_page) do
    create(
      :wiki_page,
      wiki: project.wiki,
      title: 'home',
      content: "Look at this [image](image.png)\n\n ![alt text](image.png)"
    )
  end

  # Most journeys start from an existing wiki page; only the empty-state
  # journey ("adds a home page") opts out of this.
  shared_context 'with an existing wiki page open' do
    before do
      visit wiki_page_path(project.wiki, wiki_page)
    end
  end

  before do
    sign_in(project.first_owner)
  end

  context 'when project wiki content' do
    context 'when adds a home page to the wiki' do
      it 'passes axe automated accessibility testing' do
        visit wiki_path(project.wiki)

        expect(page).to be_axe_clean.within('#content-body')

        click_link 'Create your first page'
        fill_in(:wiki_title, with: 'Home page')

        page.within('.wiki-form') do
          fill_in(:wiki_content, with: 'wiki content')
        end

        expect(page).to be_axe_clean.within('#content-body')
      end
    end

    context 'when adds a second page to the wiki' do
      include_context 'with an existing wiki page open'

      it 'passes axe automated accessibility testing' do
        expect(page).to have_css('[data-testid="wiki-page-content"]')

        click_on 'Wiki actions'
        click_on('New page')
        fill_in(:wiki_title, with: 'Second page')

        expect(page).to be_axe_clean.within('#content-body')
      end
    end

    context 'when creates a formatted page with an image' do
      include_context 'with an existing wiki page open'

      it 'passes axe automated accessibility testing' do
        expect(page).to have_css('[data-testid="wiki-page-content"]')

        expect(page).to be_axe_clean.within('#content-body').skipping :'link-in-text-block'

        click_on 'Wiki actions'
        expect(page).to be_axe_clean.within_testid('page-heading-actions')
          .skipping :'aria-allowed-role', :list, :listitem, :'nested-interactive'

        click_button 'Edit'

        page.within('.wiki-form') do
          click_button 'Switch to rich text editing'
        end

        find_by_testid('text-styles').click

        expect(page).to be_axe_clean.within('#content-body')
          .skipping :'aria-allowed-attr', :'aria-input-field-name', :'aria-prohibited-attr', :'aria-valid-attr-value'
      end
    end
  end

  context 'when project wiki structure' do
    include_context 'with an existing wiki page open'

    context 'when changes the directory path of a page' do
      it 'passes axe automated accessibility testing' do
        expect(page).to have_css('[data-testid="wiki-page-content"]')

        click_button 'Edit'
        click_button 'Edit page options'

        expect(page).to be_axe_clean.within_testid('wiki-form-actions')
      end
    end

    context 'with wiki sidebar' do
      it 'passes axe automated accessibility testing' do
        open_wiki_sidebar
        expect(page).to have_css('.wiki-sidebar')

        expect(page).to be_axe_clean.within('.wiki-sidebar')
      end
    end

    context 'with wiki list' do
      it 'passes axe automated accessibility testing' do
        open_wiki_sidebar
        expect(page).to have_css('.wiki-sidebar')
        click_on 'View all pages'

        expect(page).to be_axe_clean.within('#content-body')
      end
    end
  end
end
