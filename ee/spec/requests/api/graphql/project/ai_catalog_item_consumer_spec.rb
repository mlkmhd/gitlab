# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'Query.project.aiCatalogItemConsumerForItem', feature_category: :ai_catalog_curation do
  include Ai::Catalog::TestHelpers
  include GraphqlHelpers

  let_it_be(:owning_project) { create(:project) }
  let_it_be(:consumer_project) { create(:project, :in_group) }
  let_it_be(:user) { create(:user) }
  let_it_be(:item) { create(:ai_catalog_item, :public, project: owning_project) }

  let(:args) { { id: global_id_of(item) } }

  let(:query) do
    graphql_query_for(
      :project,
      { full_path: consumer_project.full_path },
      query_graphql_field(:ai_catalog_item_consumer_for_item,
        attributes_to_graphql(args).to_s,
        all_graphql_fields_for('AiCatalogItemConsumer', max_depth: 1)
      )
    )
  end

  let(:consumer_data) { graphql_data.dig('project', 'aiCatalogItemConsumerForItem') }

  before do
    enable_ai_catalog
  end

  context 'when the user can read item consumers on the project' do
    before_all do
      consumer_project.add_maintainer(user)
    end

    context 'when the item is enabled in the project' do
      let_it_be(:consumer) do
        create(:ai_catalog_item_consumer, item: item, project: consumer_project, enabled: true)
      end

      it 'returns the consumer with enabled=true' do
        post_graphql(query, current_user: user)

        expect(response).to have_gitlab_http_status(:success)
        expect(consumer_data).to include(
          'id' => global_id_of(consumer).to_s,
          'enabled' => true
        )
      end
    end

    context 'when the item has a disabled consumer in the project' do
      let_it_be(:consumer) do
        create(:ai_catalog_item_consumer, item: item, project: consumer_project, enabled: false)
      end

      it 'returns the consumer with enabled=false' do
        post_graphql(query, current_user: user)

        expect(response).to have_gitlab_http_status(:success)
        expect(consumer_data).to include(
          'id' => global_id_of(consumer).to_s,
          'enabled' => false
        )
      end
    end

    context 'when the item has no consumer in the project' do
      it 'returns null' do
        post_graphql(query, current_user: user)

        expect(response).to have_gitlab_http_status(:success)
        expect(consumer_data).to be_nil
      end
    end

    context 'when the item has a consumer in a different project' do
      let_it_be(:other_project) { create(:project) }
      let_it_be(:other_consumer) do
        create(:ai_catalog_item_consumer, item: item, project: other_project, enabled: true)
      end

      before_all do
        other_project.add_maintainer(user)
      end

      it 'returns null for the queried project' do
        post_graphql(query, current_user: user)

        expect(response).to have_gitlab_http_status(:success)
        expect(consumer_data).to be_nil
      end
    end

    it 'avoids N+1 database queries when loading consumers for multiple projects' do
      # We should create more consumers than the number we pass to `with_threshold`
      # to be confident that the extra queries are not due to an N+1
      consumer1 = create(:ai_catalog_item_consumer, item: item, project: consumer_project, enabled: true)
      consumer2 = create(:ai_catalog_item_consumer, item: item)
      consumer3 = create(:ai_catalog_item_consumer, item: item)

      consumer2.project.add_maintainer(user)
      consumer3.project.add_maintainer(user)

      query_without_consumers = <<~GQL
        query aiCatalogAvailableProjects {
          projects {
            nodes {
              id
              userPermissions {
                readAiCatalogItemConsumer
              }
            }
          }
        }
      GQL

      query_with_consumers = <<~GQL
        query aiCatalogAvailableProjects(
          $itemId: AiCatalogItemID!
        ) {
          projects {
            nodes {
              id
              userPermissions {
                readAiCatalogItemConsumer
              }
              aiCatalogItemConsumerForItem(id: $itemId) {
                id
              }
            }
          }
        }
      GQL

      post_graphql(query_without_consumers, current_user: user)

      control = ActiveRecord::QueryRecorder.new do
        post_graphql(query_without_consumers, current_user: user)
      end

      variables = { itemId: global_id_of(item).to_s }

      # Extra queries: consumers, items, ai_settings, and namespace_settings for root ancestors (policy checks)
      expect do
        post_graphql(query_with_consumers, variables: variables, current_user: user)
      end.not_to exceed_query_limit(control).with_threshold(4)

      returned_consumers = graphql_data.dig('projects', 'nodes').pluck('aiCatalogItemConsumerForItem')
      expect(returned_consumers).to include(
        a_graphql_entity_for(consumer1), a_graphql_entity_for(consumer2), a_graphql_entity_for(consumer3)
      )
    end
  end

  context 'when the item is inherited from the top-level group' do
    let_it_be(:group) { create(:group) }
    let_it_be(:consumer_project) { create(:project, group: create(:group, parent: group)) }
    let_it_be(:item) { create(:ai_catalog_flow, :public) }
    let_it_be(:inheritance_consumer) { create(:ai_catalog_item_consumer, :inheritance, group: group, item: item) }

    let(:query) do
      graphql_query_for(
        :project,
        { full_path: consumer_project.full_path },
        query_graphql_field(:ai_catalog_item_consumer_for_item,
          attributes_to_graphql(args).to_s,
          'id enabled consumerKind group { id }'
        )
      )
    end

    before_all do
      consumer_project.add_maintainer(user)
    end

    it 'returns the inheritance consumer to a maintainer of the project who is not a member of the group' do
      post_graphql(query, current_user: user)

      expect(response).to have_gitlab_http_status(:success)
      expect(consumer_data).to include(
        'id' => global_id_of(inheritance_consumer).to_s,
        'enabled' => true,
        'consumerKind' => 'INHERITANCE',
        'group' => { 'id' => global_id_of(group).to_s }
      )
    end

    context 'when includeInherited is false' do
      let(:args) { super().merge(include_inherited: false) }

      it 'returns null' do
        post_graphql(query, current_user: user)

        expect(response).to have_gitlab_http_status(:success)
        expect(consumer_data).to be_nil
      end
    end

    context 'when the ai_catalog_group_inherited_consumers feature flag is disabled' do
      before_all do
        group.add_developer(user)
      end

      before do
        stub_feature_flags(ai_catalog_group_inherited_consumers: false)
      end

      it 'returns null, even to a member of the group' do
        post_graphql(query, current_user: user)

        expect(response).to have_gitlab_http_status(:success)
        expect(consumer_data).to be_nil
      end
    end

    it 'separates inherited and non-inherited lookups for the same project in one request' do
      query = <<~GQL
        query($itemId: AiCatalogItemID!) {
          project(fullPath: "#{consumer_project.full_path}") {
            withInherited: aiCatalogItemConsumerForItem(id: $itemId) { id }
            ownOnly: aiCatalogItemConsumerForItem(id: $itemId, includeInherited: false) { id }
          }
        }
      GQL

      post_graphql(query, variables: { itemId: global_id_of(item).to_s }, current_user: user)

      expect(graphql_data_at(:project, :with_inherited)).to match(a_graphql_entity_for(inheritance_consumer))
      expect(graphql_data_at(:project, :own_only)).to be_nil
    end

    it 'authorizes each project separately when they share an inheritance consumer' do
      public_group = create(:group, :public)
      member_project = create(:project, :public, group: public_group, developers: user)
      non_member_project = create(:project, :public, group: public_group)
      public_group_consumer = create(:ai_catalog_item_consumer, :inheritance, group: public_group, item: item)

      query = <<~GQL
        query($itemId: AiCatalogItemID!) {
          member: project(fullPath: "#{member_project.full_path}") {
            aiCatalogItemConsumerForItem(id: $itemId) { id }
          }
          nonMember: project(fullPath: "#{non_member_project.full_path}") {
            userPermissions { readAiCatalogItemConsumer }
            aiCatalogItemConsumerForItem(id: $itemId) { id }
          }
        }
      GQL

      post_graphql(query, variables: { itemId: global_id_of(item).to_s }, current_user: user)

      expect(graphql_data_at(:member, :ai_catalog_item_consumer_for_item))
        .to match(a_graphql_entity_for(public_group_consumer))
      expect(graphql_data_at(:non_member, :user_permissions, :read_ai_catalog_item_consumer)).to be(true)
      expect(graphql_data_at(:non_member, :ai_catalog_item_consumer_for_item)).to be_nil
    end

    context 'when loading inheritance consumers for many projects' do
      let(:projects_query) do
        <<~GQL
          query aiCatalogAvailableProjects($itemId: AiCatalogItemID!) {
            projects(membership: true) {
              nodes {
                id
                aiCatalogItemConsumerForItem(id: $itemId) {
                  id
                  consumerKind
                  group { id }
                }
              }
            }
          }
        GQL
      end

      let(:variables) { { itemId: global_id_of(item).to_s } }

      def post_projects_query
        post_graphql(projects_query, variables: variables, current_user: user)
      end

      def returned_consumers
        graphql_data.dig('projects', 'nodes').to_h { |node| [node['id'], node['aiCatalogItemConsumerForItem']] }
      end

      it 'avoids N+1 database queries across projects in the same top-level group',
        :request_store, :use_sql_query_cache do
        other_subgroup_project = create(:project, group: create(:group, parent: group), maintainers: user)

        post_projects_query
        control = ActiveRecord::QueryRecorder.new(skip_cached: false) { post_projects_query }

        same_subgroup_project = create(:project, group: consumer_project.group, maintainers: user)
        nested_subgroup_project = create(:project,
          group: create(:group, parent: create(:group, parent: group)), maintainers: user)

        expect { post_projects_query }.to issue_same_number_of_queries_as(control).with_threshold(3)
        expect(returned_consumers).to match(
          global_id_of(consumer_project).to_s => a_graphql_entity_for(inheritance_consumer),
          global_id_of(other_subgroup_project).to_s => a_graphql_entity_for(inheritance_consumer),
          global_id_of(same_subgroup_project).to_s => a_graphql_entity_for(inheritance_consumer),
          global_id_of(nested_subgroup_project).to_s => a_graphql_entity_for(inheritance_consumer)
        )
      end

      def create_project_in_inheriting_group
        other_group = create(:group)
        project = create(:project, group: other_group, maintainers: user)

        [project, create(:ai_catalog_item_consumer, :inheritance, group: other_group, item: item)]
      end

      it 'avoids N+1 database queries across top-level groups with an inheritance consumer',
        :request_store, :use_sql_query_cache do
        other_group_project, other_group_consumer = create_project_in_inheriting_group

        post_projects_query
        control = ActiveRecord::QueryRecorder.new(skip_cached: false) { post_projects_query }

        third_group_project, third_group_consumer = create_project_in_inheriting_group
        fourth_group_project, fourth_group_consumer = create_project_in_inheriting_group

        expect { post_projects_query }.to issue_same_number_of_queries_as(control).with_threshold(10)
        expect(returned_consumers).to match(
          global_id_of(consumer_project).to_s => a_graphql_entity_for(inheritance_consumer),
          global_id_of(other_group_project).to_s => a_graphql_entity_for(other_group_consumer),
          global_id_of(third_group_project).to_s => a_graphql_entity_for(third_group_consumer),
          global_id_of(fourth_group_project).to_s => a_graphql_entity_for(fourth_group_consumer)
        )
      end
    end
  end

  context 'when the user cannot read item consumers on the project' do
    let_it_be(:consumer) do
      create(:ai_catalog_item_consumer, item: item, project: consumer_project, enabled: true)
    end

    before_all do
      consumer_project.add_maintainer(user)
    end

    before do
      allow(Ability).to receive(:allowed?).and_call_original
      allow(Ability).to receive(:allowed?)
        .with(user, :read_ai_catalog_item_consumer, anything)
        .and_return(false)
    end

    it 'returns null' do
      post_graphql(query, current_user: user)

      expect(response).to have_gitlab_http_status(:success)
      expect(consumer_data).to be_nil
    end
  end
end
