# frozen_string_literal: true

require 'spec_helper'

RSpec.shared_examples 'rich text editor - autocomplete' do
  include RichTextEditorHelpers

  describe 'autocomplete suggestions', feature_category: :markdown do
    let(:suggestions_dropdown) { '[data-testid="content-editor-suggestions-dropdown"]' }

    before do
      if defined?(project)
        create(:issue, project: project, title: 'My Cool Linked Issue')
        create(:merge_request, source_project: project, source_branch: 'branch-1', title: 'My Cool Merge Request')
        create(:label, project: project, title: 'My Cool Label')
        create(:milestone, project: project, title: 'My Cool Milestone')
        create(:wiki_page, wiki: project.wiki, title: 'My Cool Wiki Page', content: 'Example')

        project.add_maintainer(create(:user, name: 'abc123', username: 'abc123'))
      else # group wikis
        project = create(:project, group: group)

        create(:issue, project: project, title: 'My Cool Linked Issue')
        create(:merge_request, source_project: project, source_branch: 'branch-1', title: 'My Cool Merge Request')
        create(:group_label, group: group, title: 'My Cool Label')
        create(:milestone, group: group, title: 'My Cool Milestone')
        create(:wiki_page, wiki: group.wiki, title: 'My Cool Wiki Page', content: 'Example')

        project.add_maintainer(create(:user, name: 'abc123', username: 'abc123'))
      end

      switch_to_content_editor

      type_in_content_editor :enter
    end

    it 'shows suggestions for members with descriptions' do
      type_in_content_editor '@a'

      expect(find(suggestions_dropdown)).to have_text('abc123')

      type_in_content_editor 'bc'

      send_keys :enter

      expect(page).not_to have_css(suggestions_dropdown)
      expect(page).to have_text('@abc123')
    end

    it 'does not leave leftover parts when selecting a suggestion in the middle of a word' do
      type_in_content_editor '@abc123'

      expect(find(suggestions_dropdown)).to have_text('abc123')

      send_keys [:arrow_left, :arrow_left, :arrow_left]
      send_keys :enter

      expect(page).not_to have_css(suggestions_dropdown)
      expect(page).to have_text('@abc123')

      switch_to_markdown_editor

      expect(page.find('textarea').value).not_to include('@abc123 123')
      expect(page.find('textarea').value).to include('@abc123')
    end

    it 'allows selecting element with tab key' do
      type_in_content_editor '@abc'

      expect(find(suggestions_dropdown)).to have_text('abc123')

      send_keys :tab

      expect(page).not_to have_css(suggestions_dropdown)
      expect(page).to have_text('@abc123')
    end

    it 'allows adding text before a username' do
      type_in_content_editor '@abc'

      expect(find(suggestions_dropdown)).to have_text('abc123')

      send_keys :tab
      expect(page).to have_text('@abc123')

      send_keys [:arrow_left, :arrow_left]
      type_in_content_editor 'foo'

      sleep 0.1 # wait for the text to be added
      switch_to_markdown_editor

      expect(page.find('textarea').value).to include('foo @abc123')
    end

    it 'allows dismissing the suggestion popup and typing more text' do
      type_in_content_editor '@ab'

      expect(find(suggestions_dropdown)).to have_text('abc123')

      send_keys :escape

      expect(page).not_to have_css(suggestions_dropdown)

      type_in_content_editor :enter
      type_in_content_editor 'foobar'

      # ensure that the texts are in separate paragraphs
      expect(page).to have_selector('p', text: '@ab')
      expect(page).to have_selector('p', text: 'foobar')
      expect(page).not_to have_selector('p', text: '@abfoobar')
    end

    it 'allows typing more text after the popup has disappeared because no suggestions match' do
      type_in_content_editor '@ab'

      expect(find(suggestions_dropdown)).to have_text('abc123')

      send_keys :backspace, :backspace, :backspace
      send_keys '@abfoo'
      send_keys :enter
      send_keys 'bar'

      # ensure that the texts are in separate paragraphs
      expect(page).to have_selector('p', text: '@abfoo')
      expect(page).to have_selector('p', text: 'bar')
      expect(page).not_to have_selector('p', text: '@abfoobar')
    end

    it 'shows suggestions for merge requests' do
      type_in_content_editor '!'

      expect(find(suggestions_dropdown)).to have_text('My Cool Merge Request')

      send_keys [:arrow_down, :enter]

      expect(page).not_to have_css(suggestions_dropdown)
      expect(page).to have_text('!1')
    end

    it 'shows suggestions for issues' do
      type_in_content_editor '#'

      expect(find(suggestions_dropdown)).to have_text('My Cool Linked Issue')

      send_keys [:arrow_down, :enter]

      expect(page).not_to have_css(suggestions_dropdown)
      expect(page).to have_text('#1')
    end

    it 'shows suggestions for milestones' do
      type_in_content_editor '%'

      expect(find(suggestions_dropdown)).to have_text('My Cool Milestone')

      send_keys [:arrow_down, :enter]

      expect(page).not_to have_css(suggestions_dropdown)
      expect(page).to have_text('%My Cool Milestone')
    end

    it 'shows suggestions for emojis' do
      type_in_content_editor ':smile'

      expect(find(suggestions_dropdown)).to have_text('😃 smiley')
      expect(find(suggestions_dropdown)).to have_text('😸 smile_cat')

      send_keys :enter

      expect(page).not_to have_css(suggestions_dropdown)

      expect(page).to have_text('😄')
    end

    it 'inserts a new line on Enter while no emoji is highlighted' do
      type_in_content_editor 'Steps :'

      expect(find(suggestions_dropdown)).to have_text('grinning')

      send_keys :enter

      expect(page).not_to have_css(suggestions_dropdown)

      type_in_content_editor 'Open the page'

      expect(page).to have_selector('p', text: 'Steps :', exact_text: true)
      expect(page).to have_selector('p', text: 'Open the page', exact_text: true)
    end

    it 'closes the emoji suggestions at a space instead of matching the rest of the sentence' do
      type_in_content_editor 'Statut :'

      expect(find(suggestions_dropdown)).to have_text('grinning')

      type_in_content_editor ' '

      expect(page).not_to have_css(suggestions_dropdown)

      send_keys :enter
      type_in_content_editor 'Suite'

      expect(page).not_to have_css("#{content_editor_testid} gl-emoji")
      expect(page).to have_selector('p', text: /\AStatut :\s*\z/)
      expect(page).to have_selector('p', text: 'Suite', exact_text: true)
    end

    it 'keeps searching emoji across a space that follows the query' do
      type_in_content_editor ':smiling'

      expect(find(suggestions_dropdown)).to have_text('smiling')

      type_in_content_editor ' '

      expect(find(suggestions_dropdown)).to have_text('smiling')
    end

    it 'closes the merge request suggestions when a space follows the trigger' do
      type_in_content_editor 'Bonjour !'

      expect(find(suggestions_dropdown)).to have_text('My Cool Merge Request')

      type_in_content_editor ' '

      expect(page).not_to have_css(suggestions_dropdown)

      send_keys :enter
      type_in_content_editor 'Comment'

      expect(page).to have_selector('p', text: /\ABonjour !\s*\z/)
      expect(page).to have_selector('p', text: 'Comment', exact_text: true)
    end

    it 'shows suggestions for wiki pages' do
      type_in_content_editor '[[My'

      expect(find(suggestions_dropdown)).to have_text('My Cool Wiki Page')

      send_keys :backspace, :backspace, :backspace, :backspace
      send_keys '[[My'
      wait_for_requests
      send_keys :enter

      expect(page).not_to have_css(suggestions_dropdown)
      expect(page).to have_text('My Cool Wiki Page')

      click_button 'Switch to plain text editing'
      wait_for_requests

      # ensure serialized markdown is in correct format (gollum/wikilinks)
      expect(page.find('textarea').value).to include('[[My Cool Wiki Page|My-Cool-Wiki-Page]]')
    end

    it 'doesn\'t show suggestions dropdown if there are no suggestions to show' do
      type_in_content_editor '%'

      expect(find(suggestions_dropdown)).to have_text('My Cool Milestone')

      type_in_content_editor 'x'

      expect(page).not_to have_css(suggestions_dropdown)
    end

    it 'does not show suggestions in code blocks' do
      type_in_content_editor '```'
      type_in_content_editor :enter
      type_in_content_editor '@'
      expect(page).not_to have_css(suggestions_dropdown)
    end
  end
end
