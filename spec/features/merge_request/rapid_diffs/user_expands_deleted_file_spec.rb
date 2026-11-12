# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'Merge request > Rapid Diffs > User expands a deleted file', :js, feature_category: :code_review_workflow do
  let_it_be(:project) { create(:project, :public, :repository) }
  let_it_be(:user) { project.creator }
  let_it_be(:deleted_path) { 'files/ruby/popen.rb' }
  let_it_be(:deleted_lines) { project.repository.blob_at('master', deleted_path).data.lines.count }

  let_it_be(:merge_request) do
    project.repository.delete_file(
      user, deleted_path, message: 'Delete popen', branch_name: 'delete-popen', start_branch_name: 'master'
    )
    project.repository.update_file(
      user, 'files/ruby/version_info.rb', "puts 'changed'\n",
      message: 'Change version_info', branch_name: 'delete-popen'
    )
    create(:merge_request, source_project: project, target_project: project,
      source_branch: 'delete-popen', target_branch: 'master')
  end

  let(:deleted_file) { find('diff-file', text: deleted_path) }

  before do
    visit diffs_project_merge_request_path(project, merge_request, rapid_diffs: true)
  end

  it 'shows every removed line after selecting Show changes', :aggregate_failures do
    expect(deleted_file).to have_text('File deleted.')
    expect(deleted_file).not_to have_text('System commands must be given as an array of strings')

    deleted_file.click_button('Show changes')

    expect(deleted_file).to have_text('System commands must be given as an array of strings', wait: 20)
    expect(deleted_file).not_to have_text('File deleted.')
    expect(deleted_file).not_to have_button('Show changes')
    expect(deleted_file).to have_css('td[data-position="old"] a[data-line-number]', count: deleted_lines)
    expect(deleted_file).not_to have_css('td[data-position="new"] a[data-line-number]')
  end
end
