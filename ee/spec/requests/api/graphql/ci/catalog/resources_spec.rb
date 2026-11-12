# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'Query.ciCatalogResources', feature_category: :pipeline_composition do
  include GraphqlHelpers

  let_it_be(:user) { create(:user) }
  let_it_be(:allowed_ip) { '10.0.0.1' }
  let_it_be(:denied_ip) { '192.168.0.2' }

  let_it_be(:ip_restricted_group) do
    create(:group).tap do |group|
      create(:ip_restriction, group: group, range: '10.0.0.0/8')
    end
  end

  let_it_be(:unrestricted_group) { create(:group) }

  let_it_be(:restricted_project) do
    create(:project, :private, namespace: ip_restricted_group, reporters: user)
  end

  let_it_be(:unrestricted_project) do
    create(:project, :private, namespace: unrestricted_group, reporters: user)
  end

  let_it_be(:restricted_resource) do
    create(:ci_catalog_resource, :published, project: restricted_project)
  end

  let_it_be(:unrestricted_resource) do
    create(:ci_catalog_resource, :published, project: unrestricted_project)
  end

  let(:query) do
    <<~GQL
      query {
        ciCatalogResources {
          nodes {
            id
          }
        }
      }
    GQL
  end

  before do
    stub_licensed_features(group_ip_restriction: true)
    allow(Gitlab::IpAddressState).to receive(:current).and_return(user_ip)
  end

  context 'when the current IP is allowed by the group IP restriction' do
    let(:user_ip) { allowed_ip }

    it 'returns all resources the user has access to' do
      post_graphql(query, current_user: user)

      expect(graphql_data_at(:ciCatalogResources, :nodes)).to contain_exactly(
        a_graphql_entity_for(restricted_resource),
        a_graphql_entity_for(unrestricted_resource)
      )
    end
  end

  context 'when the current IP is not allowed by the group IP restriction' do
    let(:user_ip) { denied_ip }

    it 'does not return resources from the restricted group' do
      post_graphql(query, current_user: user)

      expect(graphql_data_at(:ciCatalogResources, :nodes)).to contain_exactly(
        a_graphql_entity_for(unrestricted_resource)
      )
    end

    it 'avoids N+1 queries' do
      ctx = { current_user: user }

      run_with_clean_state(query, context: ctx)

      control = ActiveRecord::QueryRecorder.new(skip_cached: false) do
        run_with_clean_state(query, context: ctx)
      end

      root_groups = create_list(:group, 3).each do |group|
        create(:ip_restriction, group: group, range: '10.0.0.0/8')
      end

      subgroup = create(:group, parent: root_groups.first)

      [*root_groups, subgroup].each do |group|
        create(:ci_catalog_resource, :published,
          project: create(:project, :private, namespace: group, reporters: user))
      end

      # The IP check reads ip_restrictions through project.group, which is not preloaded:
      # one ip_restrictions query per group, plus a root ancestor lookup per subgroup.
      expect do
        run_with_clean_state(query, context: ctx)
      end.not_to exceed_all_query_limit(control).with_threshold(5)
    end
  end
end
