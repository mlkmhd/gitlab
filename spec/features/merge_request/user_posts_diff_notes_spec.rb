# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'Merge request > User posts diff notes', :js, feature_category: :code_review_workflow do
  include Spec::Support::Helpers::ModalHelpers
  include RapidDiffsDiscussionHelpers

  let_it_be(:merge_request) { create(:merge_request) }
  let(:project) { merge_request.source_project }
  let(:user) { project.creator }
  let(:test_note_comment) { 'this is a test note!' }

  before do
    project.add_developer(user)
    sign_in(user)
  end

  context 'when hovering over a parallel view diff file' do
    before do
      visit diffs_project_merge_request_path(project, merge_request, view: 'parallel')
    end

    context 'with an old line on the left and no line on the right' do
      it 'allows commenting on the left side' do
        should_allow_commenting(line_by_number('files/ruby/regex.rb', 'old', 23), 'left')
      end

      it 'does not allow commenting on the right side' do
        should_not_allow_commenting(line_by_number('files/ruby/regex.rb', 'old', 23), 'right')
      end
    end

    context 'with no line on the left and a new line on the right' do
      it 'does not allow commenting on the left side' do
        should_not_allow_commenting(line_by_number('files/ruby/popen.rb', 'new', 15), 'left')
      end

      it 'allows commenting on the right side' do
        should_allow_commenting(line_by_number('files/ruby/popen.rb', 'new', 15), 'right')
      end
    end

    context 'with an old line on the left and a new line on the right' do
      it 'allows commenting on the left side' do
        should_allow_commenting(line_by_number('files/ruby/popen.rb', 'old', 9), 'left')
      end

      it 'allows commenting on the right side' do
        should_allow_commenting(line_by_number('files/ruby/popen.rb', 'old', 9), 'right')
      end
    end

    context 'with an unchanged line on the left and an unchanged line on the right' do
      it 'allows commenting on the left side' do
        should_allow_commenting(line_by_number('files/ruby/popen.rb', 'old', 7), 'left')
      end

      it 'allows commenting on the right side' do
        should_allow_commenting(line_by_number('files/ruby/popen.rb', 'old', 7), 'right')
      end
    end

    context 'with a match line' do
      it 'does not allow commenting' do
        match_should_not_allow_commenting(find('[data-hunk-header]', match: :first))
      end
    end

    context 'with an unfolded line' do
      before do
        expand_first_hunk('.gitignore')
      end

      it 'allows commenting on the left side' do
        should_allow_commenting(first_unfolded_line('.gitignore'), 'left')
      end

      it 'allows commenting on the right side' do
        # Automatically shifts comment box to left side.
        should_allow_commenting(first_unfolded_line('.gitignore'), 'right')
      end
    end
  end

  context 'when hovering over an inline view diff file' do
    before do
      visit diffs_project_merge_request_path(project, merge_request, view: 'inline')
    end

    context 'after deleting a note' do
      it 'allows commenting' do
        should_allow_commenting(line_by_number('files/ruby/popen.rb', 'new', 9))

        accept_gl_confirm(button_text: 'Delete comment') do
          within(next_discussion_row(line_by_number('files/ruby/popen.rb', 'new', 9))) do
            find('[title="More actions"] button', match: :first).click
            click_button 'Delete comment'
          end
        end

        # Wait for the discussion row to be removed before commenting again,
        # so the second click doesn't race the in-flight delete request.
        expect(line_by_number('files/ruby/popen.rb', 'new', 9))
          .to have_no_xpath('./following-sibling::*[@data-discussion-row][1]')

        should_allow_commenting(line_by_number('files/ruby/popen.rb', 'new', 9))
      end
    end

    context 'with a new line' do
      it 'allows commenting' do
        should_allow_commenting(line_by_number('files/ruby/popen.rb', 'new', 9))
      end
    end

    context 'with an old line' do
      it 'allows commenting' do
        should_allow_commenting(line_by_number('files/ruby/regex.rb', 'old', 22))
      end
    end

    context 'with an unchanged line' do
      it 'allows commenting' do
        should_allow_commenting(line_by_number('files/ruby/popen.rb', 'old', 7))
      end
    end

    context 'with a match line' do
      it 'does not allow commenting' do
        match_should_not_allow_commenting(find('[data-hunk-header]', match: :first))
      end
    end

    context 'with an unfolded line' do
      before do
        expand_first_hunk('.gitignore')
      end

      # The first expand button unfolds upwards, so the first line of the file
      # becomes the first hunk-lines row.
      let(:line_holder) { first_unfolded_line('.gitignore') }

      it 'allows commenting' do
        should_allow_commenting line_holder
      end
    end

    context 'when hovering over a diff discussion' do
      before do
        should_allow_commenting(line_by_number('files/ruby/popen.rb', 'old', 7))
        click_on 'Overview'
      end

      # The Overview tab renders diff discussions with legacy markup outside of
      # the rapid-diffs root, so the new-discussion toggle controller has no
      # rows to attach to and the toggle stays hidden along with the (now
      # display:none) Changes pane.
      it 'does not allow commenting' do
        expect(page).to have_no_testid('new_discussion_toggle')
      end
    end
  end

  context 'when cancelling the comment addition' do
    before do
      visit diffs_project_merge_request_path(project, merge_request, view: 'inline')
    end

    context 'with a new line' do
      it 'allows dismissing a comment' do
        should_allow_dismissing_a_comment(line_by_number('files/ruby/popen.rb', 'new', 9))
      end
    end
  end

  describe 'with multiple note forms' do
    before do
      visit diffs_project_merge_request_path(project, merge_request, view: 'inline')
      click_diff_line(line_by_number('files/ruby/popen.rb', 'new', 9))
    end

    describe 'posting a note' do
      it 'adds as discussion' do
        should_allow_commenting(line_by_number('files/ruby/regex.rb', 'old', 22), asset_form_reset: false)
        expect(page).to have_css('[data-testid="noteable-note-container"]', count: 1)
        expect(page).to have_field('Reply…')
      end
    end
  end

  # The expand button does nothing until the file's scripts attach, so click until the lines appear.
  # It is disabled while its request is in flight and removed once the lines land, so only an
  # enabled button is clicked, and a missing one is not waited for.
  def expand_first_hunk(file_path)
    within_diff_file(file_path) do
      wait_for('lines to expand above the first hunk') do
        has_css?('[data-hunk-lines][data-expanded]', wait: 0) || begin
          first('button[data-expand-direction]:not([disabled])', minimum: 0, wait: 0)&.click
          has_css?('[data-hunk-lines][data-expanded]', wait: 1)
        end
      end
    end
  end

  def first_unfolded_line(file_path)
    diff_file(file_path).find('[data-hunk-lines][data-expanded]', match: :first)
  end

  def write_comment_on_line(line_holder, diff_side)
    click_diff_line(line_holder, diff_side)
    next_discussion_row(line_holder).fill_in('note[note]', with: test_note_comment)
  end

  def should_allow_commenting(line_holder, diff_side = nil, asset_form_reset: true)
    write_comment_on_line(line_holder, diff_side)

    click_button 'Add comment now'

    assert_comment_persistence(line_holder, asset_form_reset: asset_form_reset)
  end

  def should_allow_dismissing_a_comment(line_holder, diff_side = nil)
    write_comment_on_line(line_holder, diff_side)

    accept_gl_confirm(_('Are you sure you want to cancel creating this comment?'), button_text: _('Discard changes')) do
      within(next_discussion_row(line_holder)) { find_by_testid('cancel').click }
    end

    assert_comment_dismissal(line_holder)
  end

  # Scoping the assertion to the row matches the actual contract -- the toggle
  # must not appear *for this line*. A wider page-level matcher is brittle: the
  # mouse trajectory to the side cell can graze adjacent rows on the way and
  # leave the toggle visible somewhere unrelated.
  def should_not_allow_commenting(line_holder, diff_side = nil)
    scroll_to_center(line_holder)
    line_cell(line_holder, diff_side).hover
    expect(line_holder).to have_no_testid('new_discussion_toggle')
  end

  def match_should_not_allow_commenting(line_holder)
    scroll_to_center(line_holder)
    line_holder.hover
    expect(line_holder).to have_no_testid('new_discussion_toggle')
  end

  def assert_comment_persistence(line_holder, asset_form_reset:)
    discussion_row = next_discussion_row(line_holder)

    expect(discussion_row).to have_content(test_note_comment)

    assert_form_is_reset if asset_form_reset
  end

  def assert_comment_dismissal(line_holder)
    expect(line_holder).to have_no_xpath('./following-sibling::*[@data-discussion-row][1]')
    expect(page).not_to have_content(test_note_comment)

    assert_form_is_reset
  end

  def assert_form_is_reset
    expect(page).to have_no_field('note[note]')
  end
end
