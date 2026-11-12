# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'validating the CODEOWNERS file of a project repository', feature_category: :source_code_management do
  include GraphqlHelpers

  let_it_be(:user) { create(:user) }
  let_it_be(:project) { create(:project, :repository, developers: user) }
  let_it_be(:ref) { 'invalid-codeowners' }

  before_all do
    project.repository.create_file(
      user,
      ::Gitlab::CodeOwners::FILE_NAME,
      "[Documentation\ndocs/*\n",
      branch_name: ref,
      message: 'Add a CODEOWNERS file with errors'
    )
  end

  it_behaves_like 'authorizing granular token permissions for GraphQL with a skipped child type',
    [:read_project, :read_code] do
    let(:boundary_object) { project }
    let(:query) do
      graphql_query_for(
        'project',
        { 'fullPath' => project.full_path },
        query_graphql_field('repository', {}, <<~GQL)
          validateCodeownerFile(ref: #{ref.inspect}) {
            total
            validationErrors {
              code
              lines
            }
          }
        GQL
      )
    end

    let(:request) { post_graphql(query, token: { personal_access_token: pat }) }
    let(:skipped_data_path) { [:project, :repository, :validate_codeowner_file, :validation_errors, 0, :code] }
  end
end
