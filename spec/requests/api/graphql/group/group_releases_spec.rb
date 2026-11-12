# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'Query.group(fullPath).releases()', feature_category: :release_orchestration do
  include GraphqlHelpers

  include_context 'when releases and group releases shared context'

  let(:resource_type) { :group }
  let(:resource) { group }

  describe "ensures that the correct data is returned based on the project's visibility and the user's access level" do
    context 'when the group is private' do
      let_it_be(:group) { create(:group, :private) }
      let_it_be_with_reload(:project) { create(:project, :repository, :private, group: group) }
      let_it_be_with_reload(:release) { create(:release, :with_evidence, project: project) }

      before_all do
        group.add_guest(guest)
        group.add_reporter(reporter)
        group.add_developer(developer)
      end

      context 'when the user is not logged in' do
        let(:current_user) { stranger }

        it_behaves_like 'no access to any release data'
      end

      context 'when the user has Guest permissions' do
        let(:current_user) { guest }

        it_behaves_like 'no access to any repository-related fields'
      end

      context 'when the user has Reporter permissions' do
        let(:current_user) { reporter }

        it_behaves_like 'full access to all repository-related fields'
        it_behaves_like 'no access to editUrl'
      end

      context 'when the user has Developer permissions' do
        let(:current_user) { developer }

        it_behaves_like 'full access to all repository-related fields'
        it_behaves_like 'access to editUrl'
      end
    end

    context 'when the group is public' do
      let_it_be(:group) { create(:group, :public) }
      let_it_be_with_reload(:project) { create(:project, :repository, :public, group: group) }
      let_it_be_with_reload(:release) { create(:release, :with_evidence, project: project) }

      before_all do
        group.add_guest(guest)
        group.add_reporter(reporter)
        group.add_developer(developer)
      end

      context 'when the user is not logged in' do
        let(:current_user) { stranger }

        it_behaves_like 'no access to any release data'
      end

      context 'when the user has Guest permissions' do
        let(:current_user) { guest }

        it_behaves_like 'full access to all repository-related fields'
        it_behaves_like 'no access to editUrl'
      end

      context 'when the user has Reporter permissions' do
        let(:current_user) { reporter }

        it_behaves_like 'full access to all repository-related fields'
        it_behaves_like 'no access to editUrl'
      end

      context 'when the user has Developer permissions' do
        let(:current_user) { developer }

        it_behaves_like 'full access to all repository-related fields'
        it_behaves_like 'access to editUrl'
      end
    end
  end

  describe 'with a fine-grained personal access token' do
    let_it_be(:group) { create(:group, :private) }
    let_it_be(:project, freeze: false) { create(:project, :repository, :private, group: group) }
    let_it_be(:release, freeze: false) { create(:release, project: project) }

    let(:user) { reporter }
    let(:boundary_object) { group }
    let(:releases_fields) { 'nodes { tagName }' }
    let(:request) do
      post_graphql(graphql_query_for(:group, { full_path: group.full_path }, "releases { #{releases_fields} }"),
        token: { personal_access_token: pat })
    end

    before_all do
      group.add_reporter(reporter)
    end

    it_behaves_like 'authorizing granular token permissions for GraphQL', [:read_group, :read_release]

    it_behaves_like 'denying a granular token that only authorizes the parent of a field', :read_group do
      let(:releases_fields) { 'count' }
      let(:parent_data_path) { %i[group] }
      let(:field_data_path) { %i[group releases] }
    end

    context 'when the token can read the releases of the group' do
      let(:pat) do
        create(:granular_pat, user: user, boundary: ::Authz::Boundary.for(group),
          permissions: %w[read_group read_release])
      end

      it 'returns the releases of its projects', :aggregate_failures do
        request

        expect(graphql_errors).to be_nil
        expect(graphql_data_at(:group, :releases, :nodes, :tag_name)).to contain_exactly(release.tag)
      end
    end
  end

  describe 'sorting and pagination' do
    let_it_be(:group) { create(:group, :public) }
    let_it_be_with_reload(:project) { create(:project, :public, group: group) }
    let(:current_user) { developer }

    let(:data_path) { [:group, :releases] }

    before_all do
      group.add_developer(developer)
    end

    def pagination_query(params)
      graphql_query_for(
        :group,
        { full_path: group.full_path },
        query_graphql_field(:releases, params, "#{page_info} nodes { tagName }")
      )
    end

    def pagination_results_data(nodes)
      nodes.pluck('tagName')
    end

    context 'when sorting by released_at' do
      let_it_be(:release5, freeze: false) do
        create(:release, project: project, tag: 'v5.5.0', released_at: 3.days.from_now)
      end

      let_it_be_with_reload(:release1) { create(:release, project: project, tag: 'v5.1.0', released_at: 3.days.ago) }
      let_it_be_with_reload(:release4) do
        create(:release, project: project, tag: 'v5.4.0', released_at: 2.days.from_now)
      end

      let_it_be_with_reload(:release2) { create(:release, project: project, tag: 'v5.2.0', released_at: 2.days.ago) }
      let_it_be_with_reload(:release3) { create(:release, project: project, tag: 'v5.3.0', released_at: 1.day.ago) }

      context 'when ascending' do
        it_behaves_like 'sorted paginated query' do
          let(:sort_param) { :RELEASED_AT_ASC }
          let(:first_param) { 2 }
          let(:all_records) { [release1.tag, release2.tag, release3.tag, release4.tag, release5.tag] }
        end
      end

      context 'when descending' do
        it_behaves_like 'sorted paginated query' do
          let(:sort_param) { :RELEASED_AT_DESC }
          let(:first_param) { 2 }
          let(:all_records) { [release5.tag, release4.tag, release3.tag, release2.tag, release1.tag] }
        end
      end

      context 'when group_releases_graphql_bounded_counts is disabled' do
        before do
          stub_feature_flags(group_releases_graphql_bounded_counts: false)
        end

        it_behaves_like 'sorted paginated query' do
          let(:sort_param) { :RELEASED_AT_DESC }
          let(:first_param) { 2 }
          let(:all_records) { [release5.tag, release4.tag, release3.tag, release2.tag, release1.tag] }
        end
      end
    end
  end

  def releases_data(args, fields)
    post_graphql(
      graphql_query_for(:group, { full_path: group.full_path }, query_graphql_field(:releases, args, fields)),
      current_user: current_user
    )

    graphql_data_at(:group, :releases)
  end

  describe 'count and last page' do
    let_it_be(:group) { create(:group, :public) }
    let_it_be(:project, freeze: false) { create(:project, :public, group: group) }
    let_it_be(:releases) do
      (1..3).map { |days| create(:release, project: project, tag: "v#{days}", released_at: days.days.ago) }
    end

    let(:current_user) { developer }

    before_all do
      group.add_developer(developer)
    end

    context 'with a count limit below the number of releases' do
      before do
        stub_const('Resolvers::GroupReleasesResolver::COUNT_LIMIT', 1)
      end

      it 'caps the count' do
        expect(releases_data({}, 'count')).to eq('count' => 2)
      end

      it 'applies an explicit limit above the cap' do
        expect(releases_data({}, 'count(limit: 5)')).to eq('count' => 3)
      end

      it 'does not cap the project releases count' do
        post_graphql(
          graphql_query_for(:project, { full_path: project.full_path }, query_graphql_field(:releases, {}, 'count')),
          current_user: current_user
        )

        expect(graphql_data_at(:project, :releases, :count)).to eq(3)
      end

      context 'when group_releases_graphql_bounded_counts is disabled' do
        before do
          stub_feature_flags(group_releases_graphql_bounded_counts: false)
        end

        it 'returns the exact count' do
          expect(releases_data({}, 'count')).to eq('count' => 3)
        end
      end

      context 'when group_releases_bounded_queries is disabled' do
        before do
          stub_feature_flags(group_releases_bounded_queries: false)
        end

        it 'caps the count' do
          expect(releases_data({}, 'count')).to eq('count' => 2)
        end
      end
    end

    describe 'last page' do
      using RSpec::Parameterized::TableSyntax

      let(:fields) { 'nodes { tagName } edges { cursor } pageInfo { hasPreviousPage hasNextPage startCursor }' }
      let(:query_args) do
        args = { sort: sort, last: last }
        next args unless before

        first_page = releases_data({ sort: sort, first: 3 }, 'pageInfo { endCursor }')
        args.merge(before: first_page.dig('pageInfo', 'endCursor'))
      end

      where(:sort, :last, :before) do
        :RELEASED_AT_DESC | 2 | false
        :RELEASED_AT_DESC | 1 | false
        :RELEASED_AT_DESC | 2 | true
        :RELEASED_AT_ASC | 2 | false
        :RELEASED_AT_ASC | 1 | false
        :RELEASED_AT_ASC | 2 | true
      end

      with_them do
        it 'returns the same page as with group_releases_graphql_bounded_counts disabled' do
          last_page = releases_data(query_args, fields)
          stub_feature_flags(group_releases_graphql_bounded_counts: false)

          expect(last_page).to eq(releases_data(query_args, fields))
        end

        context 'when group_releases_bounded_queries is disabled' do
          before do
            stub_feature_flags(group_releases_bounded_queries: false)
          end

          it 'returns the same page as with group_releases_graphql_bounded_counts disabled' do
            last_page = releases_data(query_args, fields)
            stub_feature_flags(group_releases_graphql_bounded_counts: false)

            expect(last_page).to eq(releases_data(query_args, fields))
          end
        end
      end

      it 'counts the releases only when the query selects a cursor', :aggregate_failures do
        count_queries = ->(fields) do
          ActiveRecord::QueryRecorder.new { releases_data({ last: 2 }, fields) }.log.grep(/SELECT COUNT.*"releases"/)
        end

        expect(count_queries.call('nodes { tagName } pageInfo { hasPreviousPage hasNextPage }')).to be_empty
        expect(count_queries.call('pageInfo { endCursor }').size).to eq(1)
      end

      shared_examples 'an empty last page' do
        it 'returns no releases' do
          expect(releases_data({ last: 2 }, 'nodes { tagName } pageInfo { hasPreviousPage hasNextPage }'))
            .to eq('nodes' => [], 'pageInfo' => { 'hasPreviousPage' => false, 'hasNextPage' => false })
        end
      end

      context 'when the group has no releases' do
        let_it_be(:group) { create(:group, :public) }

        before_all do
          group.add_developer(developer)
        end

        it_behaves_like 'an empty last page'
      end

      context 'when the user cannot read the group releases' do
        before do
          allow(Ability).to receive(:allowed?).and_call_original
          allow(Ability).to receive(:allowed?).with(current_user, :read_release, group).and_return(false)
        end

        it_behaves_like 'an empty last page'
      end
    end

    context 'with the group releases finder page bound' do
      where(:args) { [[{ last: 2 }], [{ first: 2 }]] }

      before do
        stub_feature_flags(group_releases_bounded_queries: true)
      end

      with_them do
        it 'reads the page through the bounded page query' do
          recorder = ActiveRecord::QueryRecorder.new { releases_data(args, 'nodes { tagName }') }
          page_reads = recorder.log.select { |sql| sql.include?('"releases"') && sql.include?('LIMIT') }

          expect(page_reads).to be_present
          expect(page_reads).to all(include(Releases::GroupReleasesFinder::PAGE_CTE_NAME.to_s))
        end
      end
    end
  end

  describe 'paging back from the last page' do
    let_it_be(:group) { create(:group, :public) }
    let_it_be(:projects, freeze: false) { create_list(:project, 2, :public, group: group) }
    let_it_be(:base_time) { Time.zone.parse('2026-01-10T00:00:00Z') }

    # Equal `released_at` values across projects exercise the `id` tiebreak at page boundaries
    let_it_be(:releases) do
      days_ago = [0, 0, 1]

      projects.flat_map do |release_project|
        days_ago.map { |days| create(:release, project: release_project, released_at: base_time - days.days) }
      end
    end

    let(:current_user) { developer }
    let(:fields) { 'nodes { tagName } pageInfo { hasPreviousPage startCursor }' }

    before_all do
      group.add_developer(developer)
    end

    where(:sort) { %i[RELEASED_AT_DESC RELEASED_AT_ASC] }

    with_them do
      it 'returns every release once, in order' do
        page = releases_data({ sort: sort, last: 2 }, fields)
        tags = page['nodes'].pluck('tagName')

        while page.dig('pageInfo', 'hasPreviousPage') && tags.size < releases.size
          page = releases_data({ sort: sort, last: 2, before: page.dig('pageInfo', 'startCursor') }, fields)
          tags = page['nodes'].pluck('tagName') + tags
        end

        expected = releases.sort_by { |release| [release.released_at, release.id] }.map(&:tag)
        expect(tags).to eq(sort == :RELEASED_AT_ASC ? expected : expected.reverse)
      end
    end
  end
end
