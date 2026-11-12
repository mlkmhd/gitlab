# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'UserAchievements', feature_category: :user_profile do
  include GraphqlHelpers

  let_it_be(:user) { create(:user) }
  let_it_be(:group) { create(:group, :private, guests: user) }
  let_it_be(:achievement) { create(:achievement, namespace: group) }
  let_it_be(:non_revoked_achievement) do
    create(:user_achievement, achievement: achievement, user: user, show_on_profile: true)
  end

  let_it_be(:revoked_achievement) do
    create(:user_achievement, :revoked, achievement: achievement, user: user, show_on_profile: true)
  end

  let_it_be(:fields) do
    <<~HEREDOC
    userAchievements {
      count
      nodes {
        id
        achievement {
          id
        }
        user {
          id
        }
        awardedByUser {
          id
        }
        revokedByUser {
          id
        }
      }
    }
    HEREDOC
  end

  let_it_be(:query) do
    graphql_query_for('user', { id: user.to_global_id.to_s }, fields)
  end

  let(:current_user) { user }

  before do
    post_graphql(query, current_user: current_user)
  end

  it_behaves_like 'a working graphql query'

  it 'returns all non_revoked user_achievements' do
    expect(graphql_data_at(:user, :userAchievements, :nodes)).to contain_exactly(
      a_graphql_entity_for(non_revoked_achievement)
    )
  end

  it 'returns the correct user_achievement count' do
    expect(graphql_data_at(:user, :userAchievements, :count)).to be(1)
  end

  it 'can lookahead to eliminate N+1 queries', :use_clean_rails_memory_store_caching do
    control = ActiveRecord::QueryRecorder.new(skip_cached: false) do
      post_graphql(query, current_user: user)
    end

    achievement2 = create(:achievement, namespace: group)
    create_list(:user_achievement, 2, achievement: achievement2, user: user)

    expect { post_graphql(query, current_user: user) }.not_to exceed_all_query_limit(control)
  end

  context 'when current user is not a member of the private group' do
    let(:current_user) { create(:user) }

    it 'returns no achievements' do
      expect(graphql_data_at(:user, :userAchievements, :nodes)).to be_empty
    end
  end

  context 'with a fine-grained personal access token' do
    # The user is not a member of this group, and reads the achievement as its recipient
    let_it_be(:non_member_group) { create(:group, :private) }
    let_it_be(:non_member_group_achievement) { create(:achievement, namespace: non_member_group) }
    let_it_be(:non_member_group_award) do
      create(:user_achievement, achievement: non_member_group_achievement, user: user, show_on_profile: true)
    end

    let(:pat) do
      create(:granular_pat, user: user, boundary: ::Authz::Boundary.for(:user), permissions: permissions,
        additional_scopes: group_scopes)
    end

    let(:group_scopes) { [] }
    let(:token_query) { query }
    let(:user_achievement_nodes) { graphql_data_at(:user, :user_achievements, :nodes) }

    before do
      post_graphql(token_query, token: { personal_access_token: pat })
    end

    context 'when the token can read achievements with the user boundary' do
      let(:permissions) { %w[read_user read_achievement] }

      it 'returns the awards and their achievements, in any awarding group', :aggregate_failures do
        expect(graphql_errors).to be_nil
        expect(user_achievement_nodes).to contain_exactly(
          a_graphql_entity_for(non_revoked_achievement, achievement: a_graphql_entity_for(achievement)),
          a_graphql_entity_for(non_member_group_award,
            achievement: a_graphql_entity_for(non_member_group_achievement))
        )
      end

      context 'when another user was awarded an achievement of a group the token owner cannot read' do
        let_it_be(:other_user) { create(:user) }
        let_it_be(:other_group_achievement) { create(:achievement, namespace: create(:group, :private)) }
        let_it_be(:other_award) do
          create(:user_achievement, achievement: other_group_achievement, user: other_user, show_on_profile: true)
        end

        let(:token_query) { graphql_query_for('user', { id: other_user.to_global_id.to_s }, fields) }

        it 'does not return the award', :aggregate_failures do
          expect(graphql_data_at(:user)).to be_present
          expect(user_achievement_nodes).not_to include(a_graphql_entity_for(other_award))
        end
      end
    end

    context 'when the token can read achievements only with a group boundary' do
      let(:permissions) { %w[read_user] }
      let(:group_scopes) { [{ boundary: ::Authz::Boundary.for(group), permissions: %w[read_achievement] }] }

      it 'does not return the awards', :aggregate_failures do
        expect(graphql_data_at(:user)).to be_present
        expect(user_achievement_nodes).to be_empty
      end
    end

    context 'when the token cannot read achievements' do
      let(:permissions) { %w[read_user] }

      it 'does not return the awards', :aggregate_failures do
        expect(graphql_data_at(:user)).to be_present
        expect(user_achievement_nodes).to be_empty
      end
    end
  end

  it_behaves_like 'authorizing granular token permissions for GraphQL with a skipped child type',
    [:read_user, :read_user_achievement] do
    let(:boundary_object) { :user }
    let(:request) { post_graphql(query, token: { personal_access_token: pat }) }
    let(:skipped_data_path) { %i[user user_achievements nodes achievement id] }
  end
end
