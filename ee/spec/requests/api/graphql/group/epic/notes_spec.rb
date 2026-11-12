# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'getting notes for an epic', feature_category: :portfolio_management do
  include GraphqlHelpers

  let(:noteable) { create(:epic) }
  let(:noteable_data) { graphql_data['group']['epic'] }

  before do
    stub_licensed_features(epics: true)
  end

  def noteable_query(noteable_fields)
    <<~QRY
      {
        group(fullPath: "#{noteable.group.full_path}") {
          epic(iid: "#{noteable.iid}") {
            #{noteable_fields}
          }
        }
      }
    QRY
  end

  it_behaves_like "exposing regular notes on a noteable in GraphQL"

  describe 'granular PAT authorization' do
    let_it_be(:user) { create(:user) }
    let_it_be(:group) { create(:group, :private, developers: user) }
    let_it_be_with_reload(:noteable) { create(:epic, group: group) }
    let_it_be(:note) { create(:note_on_epic, noteable: noteable) }

    let(:boundary_object) { group }
    let(:query) { noteable_query('discussions { nodes { id } }') }
    let(:request) { post_graphql(query, token: { personal_access_token: pat }) }

    it_behaves_like 'authorizing granular token permissions for GraphQL', [:read_group, :read_epic, :read_note]
  end
end
