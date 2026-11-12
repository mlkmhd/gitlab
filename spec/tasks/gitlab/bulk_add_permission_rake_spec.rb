# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'gitlab:import bulk add permission rake tasks', :silence_stdout, feature_category: :permissions do
  let!(:user) { create(:user) }
  let!(:admin) { create(:admin) }
  let!(:projects) { create_list(:project, 2) }

  before(:all) do
    Rake.application.rake_require 'tasks/gitlab/bulk_add_permission'
  end

  describe 'all_users_to_all_projects' do
    it 'adds users as developers and admins as maintainers, one project at a time' do
      expect(Members::Projects::CreatorService).to receive(:add_members)
        .with(an_instance_of(Project), anything, anything).exactly(4).times.and_call_original

      run_rake_task('gitlab:import:all_users_to_all_projects')

      projects.each do |project|
        expect(project.member(user).access_level).to eq(Gitlab::Access::DEVELOPER)
        expect(project.member(admin).access_level).to eq(Gitlab::Access::MAINTAINER)
      end
    end
  end

  describe 'user_to_projects' do
    it 'adds the user as a developer, one project at a time' do
      expect(Members::Projects::CreatorService).to receive(:add_members)
        .with(an_instance_of(Project), [user.id], Gitlab::Access::DEVELOPER).twice.and_call_original

      run_rake_task('gitlab:import:user_to_projects', user.email)

      projects.each do |project|
        expect(project.member(user).access_level).to eq(Gitlab::Access::DEVELOPER)
      end
    end
  end
end
