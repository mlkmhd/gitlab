# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'User creates branch', :js, feature_category: :source_code_management do
  include Features::BranchesHelpers

  let_it_be(:group) { create(:group, :public) }
  let_it_be(:user) { create(:user) }

  before do
    # The cross-document view transition on the redirect logs a console error.
    stub_feature_flags(view_transitions: false)
  end

  shared_examples 'creates new branch' do
    specify do
      branch_name = "deploy_keys_#{SecureRandom.hex(4)}"

      create_branch(branch_name)

      expect(page).to have_current_path(project_tree_path(project, branch_name))

      within_testid('branch-created-alert') do
        expect(page).to have_content("Branch #{branch_name} was created.")
        expect(page).to have_link('Create merge request',
          href: project_new_merge_request_path(project, merge_request: { source_branch: branch_name }))
      end
    end
  end

  shared_examples 'shows only the branch created alert' do
    specify do
      branch_name = "deploy_keys_#{SecureRandom.hex(4)}"

      create_branch(branch_name)

      expect(page).to have_testid('branch-created-alert', count: 1)
      expect(page).not_to have_content('You pushed to')
    end
  end

  shared_examples 'renders not found page' do
    specify do
      expect(page).to have_title('Not Found')
      expect(page).to have_content('Page not found')
    end
  end

  context 'when project has default settings' do
    let_it_be(:project) { create(:project, :repository) }

    before do
      project.add_developer(user)
      sign_in(user)

      visit new_project_branch_path(project)
    end

    it 'renders the breadcrumbs', quarantine: 'https://gitlab.com/gitlab-org/gitlab/-/issues/498887' do
      within_testid('breadcrumb-links') do
        expect(page).to have_content("#{project.creator.name} #{project.name} Branches New branch")

        expect(page).to have_link(project.creator.name, href: user_path(project.creator))
        expect(page).to have_link(project.name, href: project_path(project))
        expect(page).to have_link('Branches', href: project_branches_path(project))
        expect(page).to have_link('New branch', href: new_project_branch_path(project))
      end
    end
  end

  context 'when project is public with private repository' do
    let_it_be(:project) { create(:project, :public, :repository, :repository_private, group: group) }

    context 'when user is an inherited member from the group' do
      context 'and user is a guest' do
        before do
          group.add_guest(user)
          sign_in(user)

          visit(new_project_branch_path(project))
        end

        it_behaves_like 'renders not found page'
      end

      context 'and user is a developer' do
        before do
          group.add_developer(user)
          sign_in(user)

          visit(new_project_branch_path(project))
        end

        it_behaves_like 'creates new branch'
      end
    end
  end

  context 'when project is private' do
    let_it_be(:project) { create(:project, :private, :repository, group: group) }

    context 'when user is a direct project member' do
      context 'and user is a developer' do
        before do
          project.add_developer(user)
          sign_in(user)

          visit(new_project_branch_path(project))
        end

        context 'when on new branch page' do
          it 'renders I18n supported text' do
            page.within('#new-branch-form') do
              expect(page).to have_content(_('Branch name'))
              expect(page).to have_content(_('Create from'))
              expect(page).to have_content(_('Existing branch name, tag, or commit SHA'))
            end
          end
        end

        it_behaves_like 'creates new branch'

        context 'when the user pushed to another branch recently', :use_clean_rails_memory_store_caching do
          before do
            event = create(:push_event, project: project, author: user)
            create(:push_event_payload, event: event, ref: 'feature', action: :created)
            Users::LastPushEventService.new(user).cache_last_push_event(event)
          end

          it_behaves_like 'shows only the branch created alert'
        end

        context 'when branch name is invalid' do
          it 'does not submit and shows the error inline' do
            fill_in("branch_name", with: '1.0 stable')
            find('body').click
            click_button("Create branch")

            expect(page).to have_current_path(new_project_branch_path(project))
            expect(page).to have_css('#branch_name_error', text: 'Branch name cannot contain spaces')
            expect(page).to have_css(
              '#branch_name.is-invalid[aria-invalid="true"][aria-describedby="branch_name_error"]'
            )
          end
        end

        context 'when branch name is empty' do
          it 'does not submit and shows the error inline' do
            click_button("Create branch")

            expect(page).to have_current_path(new_project_branch_path(project))
            expect(page).to have_css('#branch_name_error', text: 'Branch name is required')
          end
        end

        context 'when branch name already exists' do
          it 'does not create new branch and shows the error inline' do
            create_branch('master')

            expect(page).to have_css('#branch_name_error', text: 'Branch already exists')
            expect(page).to have_css('#branch_name[aria-invalid="true"]')
          end
        end
      end
    end

    context 'when user is an inherited member from the group' do
      context 'and user is a guest' do
        before do
          group.add_guest(user)
          sign_in(user)

          visit(new_project_branch_path(project))
        end

        it_behaves_like 'renders not found page'
      end

      context 'and user is a developer' do
        before do
          group.add_developer(user)
          sign_in(user)

          visit(new_project_branch_path(project))
        end

        it_behaves_like 'creates new branch'
      end
    end
  end
end
