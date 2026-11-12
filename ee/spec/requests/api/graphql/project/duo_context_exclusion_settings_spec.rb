# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'Query.project(fullPath).duoContextExclusionSettings', feature_category: :ai_abstraction_layer do
  include GraphqlHelpers

  let_it_be(:project) { create(:project) }
  let_it_be(:user) { create(:user, reporter_of: project) }

  let(:query) do
    graphql_query_for(:project, { full_path: project.full_path }, 'duoContextExclusionSettings { exclusionRules }')
  end

  before_all do
    project.project_setting.update!(duo_context_exclusion_settings: { exclusion_rules: ['*.txt'] })
  end

  it_behaves_like 'authorizing granular token permissions for GraphQL with a skipped child type', :read_project do
    let(:boundary_object) { project }
    let(:skipped_data_path) { %i[project duo_context_exclusion_settings exclusion_rules] }
    let(:request) { post_graphql(query, token: { personal_access_token: pat }) }
  end
end
