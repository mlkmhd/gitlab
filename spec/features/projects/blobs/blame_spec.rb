# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'File blame', :js, feature_category: :source_code_management do
  include TreeHelper

  let_it_be(:project) { create(:project, :public, :repository) }

  let(:path) { 'CHANGELOG' }
  let(:blame_path) { project_blame_path(project, tree_join('master', path)) }

  it 'redirects to the blob viewer with blame enabled' do
    visit blame_path

    expect(page).to have_current_path(
      project_blob_path(project, tree_join('master', path), blame: 1, ref_type: 'heads')
    )
  end

  it 'preserves the line fragment through the redirect' do
    visit "#{blame_path}#L2"

    expect(page).to have_current_path(
      %r{/-/blob/master/CHANGELOG\?blame=1&ref_type=heads#L2\z}, url: true
    )
  end

  it 'renders blame information with line numbers aligned to code under the WCAG text spacing override' do
    visit blame_path
    expect(page).to have_testid('blame-commit-info')

    line_number = find_by_id('L70').ancestor('.diff-line-num')
    code_line = find_by_id('LC70')

    page.execute_script(<<~JS)
      document.head.insertAdjacentHTML('beforeend', '<style>* { line-height: 1.5 !important; letter-spacing: 0.12em !important; word-spacing: 0.16em !important; }</style>');
    JS

    expect(code_line.rect.y).to be_within(1).of(line_number.rect.y)
  end

  context 'with a binary file' do
    let(:path) { 'files/images/logo-black.png' }

    it 'redirects to the blob viewer without blame' do
      visit blame_path

      expect(page).to have_current_path(project_blob_path(project, tree_join('master', path)))
      expect(page).to have_content('Blame for binary files is not supported.')
    end
  end
end
