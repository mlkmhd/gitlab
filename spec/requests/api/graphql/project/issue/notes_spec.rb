# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'getting notes for an issue', feature_category: :team_planning do
  include GraphqlHelpers

  let(:noteable) { create(:issue) }
  let(:noteable_data) { graphql_data['project']['issue'] }

  def noteable_query(noteable_fields)
    <<~QRY
      {
        project(fullPath: "#{noteable.project.full_path}") {
          issue(iid: "#{noteable.iid}") {
            #{noteable_fields}
          }
        }
      }
    QRY
  end

  it_behaves_like 'exposing regular notes on a noteable in GraphQL'

  describe 'granular PAT authorization' do
    let_it_be(:user) { create(:user) }
    let_it_be(:project) { create(:project, :private, developers: user) }
    let_it_be(:noteable) { create(:issue, project: project) }
    let_it_be(:note) { create(:discussion_note_on_issue, noteable: noteable, project: project) }

    let(:boundary_object) { project }
    let(:query) { noteable_query('discussions { nodes { id } }') }
    let(:request) { post_graphql(query, token: { personal_access_token: pat }) }

    it_behaves_like 'authorizing granular token permissions for GraphQL', [:read_project, :read_issue, :read_note]
  end
end
