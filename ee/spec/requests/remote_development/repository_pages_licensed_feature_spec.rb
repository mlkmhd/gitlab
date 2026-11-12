# frozen_string_literal: true

require 'spec_helper'

# MSW specs inject the licensed feature, so only this catches a controller dropping the push.
RSpec.describe 'Remote Development licensed feature on repository pages', feature_category: :workspaces do
  using RSpec::Parameterized::TableSyntax

  let_it_be(:project) { create(:project, :public, :repository) }

  let(:paths) do
    {
      overview: project_path(project),
      tree: project_tree_path(project, project.default_branch),
      blob: project_blob_path(project, "#{project.default_branch}/README.md")
    }
  end

  where(:page, :licensed) do
    :overview | true
    :overview | false
    :tree     | true
    :tree     | false
    :blob     | true
    :blob     | false
  end

  with_them do
    before do
      stub_licensed_features(remote_development: licensed)
    end

    it 'pushes the remote_development licensed feature' do
      get paths.fetch(page)

      expect(response).to have_gitlab_http_status(:ok)
      expect(response.body).to have_pushed_licensed_features(remoteDevelopment: licensed)
    end
  end
end
