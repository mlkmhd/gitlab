# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'Query group release stats', feature_category: :release_orchestration do
  include GraphqlHelpers

  let_it_be(:group) { create(:group, :private) }
  let_it_be(:subgroup) { create(:group, :private, parent: group) }
  let_it_be_with_reload(:project) { create(:project, group: subgroup) }
  let_it_be(:release) { create(:release, project: project) }
  let_it_be(:user) { create(:user, guest_of: group) }

  let(:queried_group) { subgroup }

  let(:query) do
    graphql_query_for(
      'group',
      { 'fullPath' => queried_group.full_path },
      query_graphql_path(%i[stats releaseStats], 'releasesCount releasesPercentage')
    )
  end

  let(:release_stats) { graphql_data_at(:group, :stats, :release_stats) }

  subject(:request) { post_graphql(query, current_user: user) }

  before do
    stub_licensed_features(group_ci_cd_analytics_releases: true)
  end

  it 'returns the release stats' do
    request

    expect(release_stats).to eq('releasesCount' => 1, 'releasesPercentage' => 100)
  end

  context 'with a fine-grained personal access token' do
    let(:boundary_object) { queried_group }
    let(:request) { post_graphql(query, token: { personal_access_token: pat }) }

    it_behaves_like 'authorizing granular token permissions for GraphQL', [:read_group, :read_release]

    it_behaves_like 'denying a granular token that only authorizes the parent of a field', :read_group do
      let(:parent_data_path) { %i[group stats] }
      let(:field_data_path) { %i[group stats release_stats] }
    end

    context 'when the token can read the releases of the group' do
      let(:pat) do
        create(:granular_pat, user: user, boundary: ::Authz::Boundary.for(queried_group),
          permissions: %w[read_group read_release])
      end

      it 'returns the release stats', :aggregate_failures do
        request

        expect(graphql_errors).to be_nil
        expect(release_stats).to eq('releasesCount' => 1, 'releasesPercentage' => 100)
      end
    end
  end

  context 'when querying a subgroup' do
    it_behaves_like 'storing arguments in the application context' do
      let(:expected_params) { { root_namespace: group.full_path } }
    end
  end

  context 'when querying the top-level group' do
    let(:queried_group) { group }

    it_behaves_like 'storing arguments in the application context' do
      let(:expected_params) { { root_namespace: group.full_path } }
    end
  end

  context 'when only one field is requested' do
    using RSpec::Parameterized::TableSyntax

    where(field: %w[releasesCount releasesPercentage])

    with_them do
      let(:query) do
        graphql_query_for(
          'group',
          { 'fullPath' => queried_group.full_path },
          query_graphql_path(%i[stats releaseStats], field)
        )
      end

      it_behaves_like 'storing arguments in the application context' do
        let(:expected_params) { { root_namespace: group.full_path } }
      end
    end
  end

  context 'when the user cannot read release stats' do
    before do
      stub_licensed_features(group_ci_cd_analytics_releases: false)
    end

    it 'returns no stats and does not record the namespace' do
      allow(Labkit::Context).to receive(:pop)

      request

      expect(release_stats).to be_nil
      expect(Gitlab::ApplicationContext.current).not_to include('meta.root_namespace')
    end
  end
end
