# frozen_string_literal: true

require 'spec_helper'

# Records the REST requests the shared ref selector sends (Api.branches and Api.tags),
# so every integration domain that mounts it gets real responses.
RSpec.describe 'Ref selector Integration (REST fixtures)', type: :request, feature_category: :source_code_management do
  include ApiHelpers
  include JavaScriptFixturesHelpers

  # A small repository instead of the seeded one: its first page of branches carries a
  # 5 MB commit subject, and the refs the specs pick would sit past that page.
  let_it_be(:project) { create(:project, :custom_repo, files: { 'README.md' => '# Ref selector' }) }
  let_it_be(:user) { create(:user, developer_of: project) }

  let_it_be(:refs) do
    %w[feature improve/awesome].each { |branch| project.repository.add_branch(user, branch, 'master') }
    project.repository.add_tag(user, 'v1.0.0', 'master')
  end

  # Matches DEFAULT_PER_PAGE in app/assets/javascripts/api.js.
  let(:params) { { search: '', per_page: 20 } }

  base_output_path = 'ref_selector/integration/'

  it "#{base_output_path}branches.json" do
    get api("/projects/#{project.id}/repository/branches", user), params: params

    expect(response).to have_gitlab_http_status(:ok)
    expect(json_response.pluck('name')).to contain_exactly('master', 'feature', 'improve/awesome')
  end

  it "#{base_output_path}tags.json" do
    get api("/projects/#{project.id}/repository/tags", user), params: params

    expect(response).to have_gitlab_http_status(:ok)
    expect(json_response.pluck('name')).to contain_exactly('v1.0.0')
  end
end
