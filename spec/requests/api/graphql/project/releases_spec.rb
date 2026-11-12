# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'Query.project(fullPath).releases()', feature_category: :release_orchestration do
  include GraphqlHelpers

  include_context 'when releases and group releases shared context'

  let(:resource_type) { :project }
  let(:resource) { project }

  describe "ensures that the correct data is returned based on the project's visibility and the user's access level" do
    context 'when the project is private' do
      let_it_be(:project, freeze: false) { create(:project, :repository, :private) }
      let_it_be(:release, freeze: false) { create(:release, :with_evidence, project: project) }

      before_all do
        project.add_guest(guest)
        project.add_reporter(reporter)
        project.add_developer(developer)
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

    context 'when the project is public' do
      let_it_be(:project, freeze: false) { create(:project, :repository, :public) }
      let_it_be(:release, freeze: false) { create(:release, :with_evidence, project: project) }

      before_all do
        project.add_guest(guest)
        project.add_reporter(reporter)
        project.add_developer(developer)
      end

      context 'when the user is not logged in' do
        let(:current_user) { stranger }

        it_behaves_like 'full access to all repository-related fields'
        it_behaves_like 'no access to editUrl'
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
    using RSpec::Parameterized::TableSyntax

    let_it_be(:project, freeze: false) { create(:project, :repository, :private) }
    let_it_be(:release, freeze: false) { create(:release, :with_evidence, project: project) }
    let_it_be(:release_link, freeze: false) { create(:release_link, release: release) }

    let(:user) { reporter }
    let(:boundary_object) { project }
    let(:release_fields) { 'tagName' }
    let(:releases_fields) { "nodes { #{release_fields} }" }
    let(:request) do
      post_graphql(graphql_query_for(:project, { full_path: project.full_path }, "releases { #{releases_fields} }"),
        token: { personal_access_token: pat })
    end

    before_all do
      project.add_reporter(reporter)
    end

    it_behaves_like 'authorizing granular token permissions for GraphQL', [:read_project, :read_release]

    it_behaves_like 'denying a granular token that only authorizes the parent of a field', :read_project do
      let(:releases_fields) { 'count' }
      let(:parent_data_path) { %i[project] }
      let(:field_data_path) { %i[project releases] }
    end

    where(:release_fields, :child_path) do
      'assets { count }' | [:assets, :count]
      'assets { links { nodes { name } } }' | [:assets, :links, :nodes, 0, :name]
      'assets { sources { nodes { format } } }' | [:assets, :sources, :nodes, 0, :format]
      'evidences { nodes { sha } }' | [:evidences, :nodes, 0, :sha]
      'links { selfUrl }' | [:links, :self_url]
    end

    with_them do
      it_behaves_like 'authorizing granular token permissions for GraphQL with a skipped child type',
        [:read_project, :read_release] do
        let(:skipped_data_path) { [:project, :releases, :nodes, 0, *child_path] }
      end
    end
  end

  describe 'sorting and pagination' do
    let_it_be(:sort_project, freeze: false) { create(:project, :public) }

    let(:data_path)          { [:project, :releases] }
    let(:current_user)       { developer }

    def pagination_query(params)
      graphql_query_for(
        resource_type,
        { full_path: sort_project.full_path },
        query_graphql_field(:releases, params, "#{page_info} nodes { tagName }")
      )
    end

    def pagination_results_data(nodes)
      nodes.map { |release| release['tagName'] }
    end

    context 'when sorting by released_at' do
      let_it_be(:release5, freeze: false) do
        create(:release, project: sort_project, tag: 'v5.5.0', released_at: 3.days.from_now)
      end

      let_it_be(:release1, freeze: false) do
        create(:release, project: sort_project, tag: 'v5.1.0', released_at: 3.days.ago)
      end

      let_it_be(:release4, freeze: false) do
        create(:release, project: sort_project, tag: 'v5.4.0', released_at: 2.days.from_now)
      end

      let_it_be(:release2, freeze: false) do
        create(:release, project: sort_project, tag: 'v5.2.0', released_at: 2.days.ago)
      end

      let_it_be(:release3, freeze: false) do
        create(:release, project: sort_project, tag: 'v5.3.0', released_at: 1.day.ago)
      end

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
    end

    context 'when sorting by created_at' do
      let_it_be(:release5, freeze: false) do
        create(:release, project: sort_project, tag: 'v5.5.0', created_at: 3.days.from_now)
      end

      let_it_be(:release1, freeze: false) do
        create(:release, project: sort_project, tag: 'v5.1.0', created_at: 3.days.ago)
      end

      let_it_be(:release4, freeze: false) do
        create(:release, project: sort_project, tag: 'v5.4.0', created_at: 2.days.from_now)
      end

      let_it_be(:release2, freeze: false) do
        create(:release, project: sort_project, tag: 'v5.2.0', created_at: 2.days.ago)
      end

      let_it_be(:release3, freeze: false) do
        create(:release, project: sort_project, tag: 'v5.3.0', created_at: 1.day.ago)
      end

      context 'when ascending' do
        it_behaves_like 'sorted paginated query' do
          let(:sort_param) { :CREATED_ASC }
          let(:first_param) { 2 }
          let(:all_records) { [release1.tag, release2.tag, release3.tag, release4.tag, release5.tag] }
        end
      end

      context 'when descending' do
        it_behaves_like 'sorted paginated query' do
          let(:sort_param) { :CREATED_DESC }
          let(:first_param) { 2 }
          let(:all_records) { [release5.tag, release4.tag, release3.tag, release2.tag, release1.tag] }
        end
      end
    end
  end

  describe 'avoiding a Gitaly N+1 when resolving release commits', :request_store do
    let_it_be_with_reload(:n_plus_one_project) { create(:project, :repository, :public) }
    let_it_be(:n_plus_one_user) { create(:user, developer_of: n_plus_one_project) }

    # More releases than MAXIMUM_GITALY_CALLS, each on a distinct commit, so an
    # un-batched resolve trips the built-in Gitaly N+1 detector.
    let_it_be(:release_count) do
      shas = n_plus_one_project.repository
        .commits('master', limit: Gitlab::GitalyClient::MAXIMUM_GITALY_CALLS + 5)
        .map(&:id).uniq

      shas.each_with_index do |sha, index|
        create(:release, project: n_plus_one_project, tag: "n-plus-one-#{index}", sha: sha, author: n_plus_one_user)
      end

      shas.size
    end

    specify do
      # sanity check for the essential test setup pre-condition
      expect(release_count).to be > Gitlab::GitalyClient::MAXIMUM_GITALY_CALLS
    end

    it 'resolves every release commit within the Gitaly call limit' do
      query = graphql_query_for(:project, { fullPath: n_plus_one_project.full_path },
        %(releases(first: #{release_count}) { nodes { commit { id sha webUrl title } } }))

      post_graphql(query, current_user: n_plus_one_user)

      expect_graphql_errors_to_be_empty
      nodes = graphql_data.dig('project', 'releases', 'nodes')
      expect(nodes.size).to eq(release_count)
      expect(nodes).to all(include('commit' => include('sha')))
    end
  end
end
