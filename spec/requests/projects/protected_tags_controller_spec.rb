# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Projects::ProtectedTagsController, feature_category: :source_code_management do
  describe "GET #index" do
    let_it_be(:project) { create(:project) }
    let_it_be(:user) { create(:user, maintainer_of: project) }

    before do
      sign_in(user)
    end

    it "redirects to the repository settings page" do
      get project_protected_tags_path(project)

      expect(response).to redirect_to(project_settings_repository_path(project))
    end
  end

  describe "GET #show" do
    let_it_be_with_reload(:project) { create(:project, :repository) }
    let(:user) { create(:user, maintainer_of: project) }
    let(:protected_tag) { create(:protected_tag, project: project, name: 'v*') }

    before do
      sign_in(user)
    end

    it_behaves_like 'hides the settings search bar' do
      subject { get project_protected_tag_path(project, protected_tag) }
    end
  end

  describe "DELETE #destroy" do
    let(:project) { create(:project) }
    let(:protected_tag) { create(:protected_tag, :developers_can_create, project: project) }
    let(:user) { create(:user) }

    before do
      project.add_maintainer(user)
      sign_in(user)
    end

    it "deletes the protected tag" do
      delete project_protected_tag_path(project, protected_tag)

      expect { ProtectedTag.find(protected_tag.id) }.to raise_error(ActiveRecord::RecordNotFound)
    end
  end
end
