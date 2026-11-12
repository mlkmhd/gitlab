# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'projects/_branch_created', feature_category: :source_code_management do
  let_it_be(:project) { build_stubbed(:project) }
  let(:branch_name) { 'feature/login' }

  before do
    assign(:project, project)
    allow(view).to receive(:create_mr_button?).with(source_project: project, from: branch_name)
      .and_return(can_create_mr)

    render 'projects/branch_created', branch_name: branch_name
  end

  context 'when the user can create a merge request' do
    let(:can_create_mr) { true }

    it 'names the branch with a link and a copy button' do
      expect(rendered).to have_content('Branch feature/login was created.')
      expect(rendered).to have_link('feature/login', href: project_commits_path(project, branch_name))
      expect(rendered).to have_button('Copy branch name')
    end

    it 'shows a create merge request button' do
      expect(rendered).to have_link('Create merge request',
        href: project_new_merge_request_path(project, merge_request: { source_branch: branch_name }))
    end
  end

  context 'when the user cannot create a merge request' do
    let(:can_create_mr) { false }

    it 'does not show a create merge request button' do
      expect(rendered).to have_content('Branch feature/login was created.')
      expect(rendered).not_to have_link('Create merge request')
    end
  end
end
