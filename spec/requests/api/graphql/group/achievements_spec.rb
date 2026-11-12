# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'getting the achievements of a group', feature_category: :user_profile do
  include GraphqlHelpers

  let_it_be(:user) { create(:user) }
  let_it_be(:group) { create(:group, :private, guests: user) }
  let_it_be(:achievement) { create(:achievement, namespace: group) }
  let_it_be(:user_achievement) { create(:user_achievement, achievement: achievement, user: user) }

  let(:query) do
    graphql_query_for('group', { full_path: group.full_path }, [
      query_graphql_field(:achievements, nil, 'nodes { id userAchievements { nodes { id } } }')
    ])
  end

  let(:achievement_nodes) { graphql_data_at(:group, :achievements, :nodes) }
  let(:award_nodes) { graphql_data_at(:group, :achievements, :nodes, :user_achievements, :nodes) }

  it_behaves_like 'authorizing granular token permissions for GraphQL', [:read_group, :read_achievement] do
    let(:boundary_object) { group }
    let(:request) { post_graphql(query, token: { personal_access_token: pat }) }
  end

  it_behaves_like 'authorizing granular token permissions for GraphQL with a skipped child type',
    [:read_group, :read_achievement] do
    let(:boundary_object) { group }
    let(:request) { post_graphql(query, token: { personal_access_token: pat }) }
    let(:skipped_data_path) { %i[group achievements nodes id] }
  end

  context 'with a fine-grained personal access token' do
    let(:pat) do
      create(:granular_pat, user: user, boundary: ::Authz::Boundary.for(group), permissions: permissions,
        additional_scopes: user_scopes)
    end

    let(:user_scopes) { [] }

    before do
      post_graphql(query, token: { personal_access_token: pat })
    end

    context 'when the token can read the group and its achievements' do
      let(:permissions) { %w[read_group read_achievement] }

      it 'returns the achievements without their awards', :aggregate_failures do
        expect(graphql_errors).to be_nil
        expect(achievement_nodes).to contain_exactly(a_graphql_entity_for(achievement))
        expect(award_nodes).to be_empty
      end

      context 'when the token can also read achievements with the user boundary' do
        let(:user_scopes) { [{ boundary: ::Authz::Boundary.for(:user), permissions: %w[read_achievement] }] }

        it 'returns the achievements and their awards', :aggregate_failures do
          expect(graphql_errors).to be_nil
          expect(achievement_nodes).to contain_exactly(a_graphql_entity_for(achievement))
          expect(award_nodes).to contain_exactly(a_graphql_entity_for(user_achievement))
        end
      end
    end

    context 'when the token can only read the group' do
      let(:permissions) { %w[read_group] }

      it 'does not return the achievements', :aggregate_failures do
        expect(graphql_data_at(:group)).to be_present
        expect(graphql_data_at(:group, :achievements)).to be_nil
      end
    end

    context 'when the token can read achievements only with the user boundary' do
      let(:permissions) { %w[read_group] }
      let(:user_scopes) { [{ boundary: ::Authz::Boundary.for(:user), permissions: %w[read_achievement] }] }

      it 'does not return the achievements', :aggregate_failures do
        expect(graphql_data_at(:group)).to be_present
        expect(graphql_data_at(:group, :achievements)).to be_nil
      end
    end
  end
end
