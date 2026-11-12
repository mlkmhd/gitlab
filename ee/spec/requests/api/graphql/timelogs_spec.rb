# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'Timelogs', feature_category: :team_planning do
  include GraphqlHelpers

  let_it_be(:user) { create(:user) }
  let_it_be(:group) { create(:group, developers: user) }
  let_it_be_with_reload(:epic) { create(:work_item, :epic, namespace: group) }
  let_it_be(:timelog) { create(:timelog, user: user, issue: WorkItem.find(epic.id)) }

  before do
    stub_licensed_features(epics: true)
  end

  context 'with a timelog on a group-level work item' do
    it 'returns the timelog with a null project and the full group reference' do
      post_graphql(
        graphql_query_for(:timelogs, { username: user.username },
          'nodes { id project { id } issue { reference(full: true) } }'),
        current_user: user
      )

      expect(graphql_errors).to be_nil
      expect(graphql_data_at(:timelogs, :nodes)).to contain_exactly(
        {
          'id' => global_id_of(timelog).to_s,
          'project' => nil,
          'issue' => { 'reference' => "#{group.full_path}##{epic.iid}" }
        }
      )
    end
  end
end
