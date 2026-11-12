# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'Projects > Show > User sees citation support', feature_category: :groups_and_projects do
  let(:user) { create(:user, :with_namespace) }
  let(:project) { create(:project, :public, :repository) }
  let(:presenter) { project.present(current_user: user) }

  let(:citation_content) do
    <<~CFF
      authors:
        - family-names: Doe
          given-names: Jane
      cff-version: 1.2.0
      message: "If you use this software, please cite it using these metadata."
      title: "Test Project"
    CFF
  end

  def create_citation_file
    Files::CreateService.new(
      project,
      project.creator,
      start_branch: 'master',
      branch_name: 'master',
      commit_message: 'Add CITATION.cff',
      file_path: 'CITATION.cff',
      file_content: citation_content
    ).execute
  end

  describe 'as a maintainer' do
    before do
      project.add_maintainer(user)
      sign_in(user)
    end

    context 'when the project has a CITATION.cff file' do
      before do
        create_citation_file
      end

      it 'shows the "CITATION.cff" button linked to the file' do
        visit project_path(project)

        expect(project.repository.citation_blob).not_to be_nil

        within_testid('project-buttons') do
          expect(page).to have_link('CITATION.cff', href: presenter.citation_path)
        end
      end

      it 'shows the citation header on the blob page' do
        visit project_blob_path(project, 'master/CITATION.cff')

        expect(page).to have_content('please cite it using the metadata in this file')
        expect(page).to have_link('Learn more about CITATION.cff files.')
      end
    end

    context 'when the project does not have a CITATION.cff file' do
      it 'shows the "Add CITATION.cff" button linked to the new file page' do
        visit project_path(project)

        within_testid('project-buttons') do
          expect(page).to have_link('Add CITATION.cff', href: presenter.add_citation_path)
        end
      end
    end
  end

  describe 'as a normal user' do
    before do
      sign_in(user)
    end

    it 'does not show the citation button' do
      visit project_path(project)

      within_testid('project-buttons') do
        expect(page).not_to have_link('Add CITATION.cff')
      end
    end
  end
end
