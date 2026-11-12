# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'Projects > Show > User with limited access', feature_category: :groups_and_projects do
  let(:project) { create(:project, :private, :repository, :wiki_repo) }

  let(:code_info) { '[data-testid="no-code-access-info"]' }
  let(:wiki_info) { '[data-testid="no-wiki-access-info"]' }

  context 'when signed in as a guest of a private project' do
    let(:guest) { create(:user, :with_namespace, guest_of: project) }

    before do
      sign_in(guest)
    end

    context 'when the wiki has no homepage', :js do
      it 'shows the activity feed and explains the missing code access in a popover' do
        visit project_path(project)

        expect(page).to have_css('.project-show-activity')
        expect(page).to have_no_content('This project does not have a wiki homepage yet')
        expect(page).to have_no_css(wiki_info)

        find(code_info).click

        within('.gl-popover') do
          expect(page).to have_content("You don't have access to this project's code")
          expect(page).to have_link('Which roles can view code?')
          expect(page).to have_link('View project members', href: project_project_members_path(project))
        end
      end
    end

    context 'when the wiki has a homepage' do
      before do
        create(:wiki_page, wiki: project.wiki, title: 'home', content: 'Welcome to the wiki')
      end

      it 'shows the wiki homepage and the missing code access' do
        visit project_path(project)

        expect(page).to have_content('Welcome to the wiki')
        expect(page).to have_css(code_info, text: 'No access to code')
      end
    end
  end

  context 'when signed in as a guest of a public project with the wiki preference' do
    let(:project) { create(:project, :public, :repository, :wiki_repo) }
    let(:guest) { create(:user, :with_namespace, guest_of: project, project_view: :wiki) }

    before do
      sign_in(guest)
    end

    it 'shows the repository when the wiki has no homepage' do
      visit project_path(project)

      expect(page).to have_link('README')
      expect(page).to have_no_content('This project does not have a wiki homepage yet')
      expect(page).to have_no_css(code_info)
    end
  end

  context 'when signed in as a non-member of a public project' do
    let(:non_member) { create(:user, :with_namespace, project_view: :wiki) }

    before do
      sign_in(non_member)
    end

    context 'with a members-only repository and wiki' do
      let(:project) do
        create(:project, :public, :repository, :wiki_repo, :repository_private, wiki_access_level: ProjectFeature::PRIVATE)
      end

      it 'shows the activity feed and both missing access lines' do
        visit project_path(project)

        expect(page).to have_css('.project-show-activity')
        expect(page).to have_css(code_info, text: 'No access to code')
        expect(page).to have_css(wiki_info, text: 'No access to wiki')
      end
    end

    context 'with a members-only wiki' do
      let(:project) { create(:project, :public, :repository, :wiki_repo, wiki_access_level: ProjectFeature::PRIVATE) }

      it 'shows the repository instead of the wiki preference' do
        visit project_path(project)

        expect(page).to have_link('README')
        expect(page).to have_no_content('This project does not have a wiki homepage yet')
        expect(page).to have_css(wiki_info, text: 'No access to wiki')
        expect(page).to have_no_css(code_info)
      end
    end
  end

  context 'when signed in as a developer' do
    let(:developer) { create(:user, :with_namespace, developer_of: project) }

    before do
      sign_in(developer)
    end

    it 'shows the repository without missing access lines' do
      visit project_path(project)

      expect(page).to have_link('README')
      expect(page).to have_no_css(code_info)
      expect(page).to have_no_css(wiki_info)
    end
  end
end
