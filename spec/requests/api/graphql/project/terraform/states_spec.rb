# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'query terraform states', feature_category: :infrastructure_as_code do
  include GraphqlHelpers
  include ::API::Helpers::RelatedResourcesHelpers

  let_it_be(:project) { create(:project) }
  let_it_be(:terraform_state) { create(:terraform_state, :with_version, :locked, project: project) }
  let_it_be(:latest_version) { terraform_state.latest_version }

  let(:query) do
    graphql_query_for(
      :project,
      { fullPath: project.full_path },
      %(
        terraformStates {
          count
          nodes {
            id
            name
            lockedAt
            createdAt
            updatedAt

            latestVersion {
              id
              downloadPath
              serial
              createdAt
              updatedAt

              createdByUser {
                id
              }

              job {
                name
              }
            }

            lockedByUser {
              id
            }
          }
        }
      )
    )
  end

  let(:current_user) { project.creator }
  let(:data) { graphql_data.dig('project', 'terraformStates') }

  it_behaves_like 'authorizing granular token permissions for GraphQL', [:read_project, :read_terraform_state] do
    let(:user) { create(:user, maintainer_of: project) }
    let(:boundary_object) { project }
    let(:request) do
      post_graphql(
        graphql_query_for(:project, { fullPath: project.full_path },
          'terraformStates { nodes { id latestVersion { id } } }'),
        token: { personal_access_token: pat }
      )
    end
  end

  before do
    post_graphql(query, current_user: current_user)
  end

  it 'returns terraform state data' do
    download_path = expose_path(
      api_v4_projects_terraform_state_versions_path(
        id: project.id,
        name: terraform_state.name,
        serial: latest_version.version
      )
    )

    expect(data['nodes']).to contain_exactly a_graphql_entity_for(
      terraform_state, :name,
      'lockedAt' => terraform_state.locked_at.iso8601,
      'createdAt' => terraform_state.created_at.iso8601,
      'updatedAt' => terraform_state.updated_at.iso8601,
      'lockedByUser' => a_graphql_entity_for(terraform_state.locked_by_user),
      'latestVersion' => a_graphql_entity_for(
        latest_version,
        'serial' => eq(latest_version.version),
        'downloadPath' => eq(download_path),
        'createdAt' => eq(latest_version.created_at.iso8601),
        'updatedAt' => eq(latest_version.updated_at.iso8601),
        'createdByUser' => a_graphql_entity_for(latest_version.created_by_user),
        'job' => { 'name' => eq(latest_version.build.name) }
      )
    )
  end

  it 'returns count of terraform states' do
    count = data['count']
    expect(count).to be(project.terraform_states.size)
  end

  context 'unauthorized users' do
    let(:current_user) { nil }

    it { expect(data).to be_nil }
  end

  describe 'versions' do
    # StateVersion touches its state on create, which a frozen let_it_be record rejects.
    let_it_be(:older_version) do
      create(:terraform_state_version,
        terraform_state: Terraform::State.find(terraform_state.id), version: latest_version.version - 1)
    end

    let_it_be(:other_state_version) do
      create(:terraform_state_version, terraform_state: create(:terraform_state, project: project))
    end

    let(:fields) do
      %(
        terraformStates {
          nodes {
            name
            versions#{versions_args} {
              nodes {
                id
                serial
              }
              pageInfo {
                hasNextPage
                endCursor
              }
            }
          }
        }
      )
    end

    let(:versions_args) { '' }
    let(:query) { graphql_query_for(:project, { fullPath: project.full_path }, fields) }
    let(:state_data) { data['nodes'].find { |node| node['name'] == terraform_state.name } }

    it 'returns every version of the state, most recent first' do
      expect(state_data['versions']['nodes']).to match([
        a_graphql_entity_for(latest_version, 'serial' => latest_version.version),
        a_graphql_entity_for(older_version, 'serial' => older_version.version)
      ])
      expect(state_data['versions']['pageInfo']['hasNextPage']).to be(false)
    end

    context 'when the versions field is requested through aliases', :aggregate_failures do
      let(:fields) do
        %(
          terraformStates {
            nodes {
              name
              left: versions(first: 3) {
                nodes { id serial }
                pageInfo { hasNextPage }
              }
              right: versions(first: 3) {
                nodes { id serial }
                pageInfo { hasNextPage }
              }
            }
          }
        )
      end

      it 'returns each version once with no next page for both aliases' do
        %w[left right].each do |alias_name|
          expect(state_data[alias_name]['nodes']).to match([
            a_graphql_entity_for(latest_version, 'serial' => latest_version.version),
            a_graphql_entity_for(older_version, 'serial' => older_version.version)
          ])
          expect(state_data[alias_name]['pageInfo']['hasNextPage']).to be(false)
        end
      end
    end

    it 'does not leak versions of other states' do
      version_ids = data['nodes'].flat_map { |node| node['versions']['nodes'].pluck('id') }

      expect(version_ids).to include(other_state_version.to_global_id.to_s)
      expect(state_data['versions']['nodes'].pluck('id')).not_to include(other_state_version.to_global_id.to_s)
    end

    it 'loads the versions of every state without a query per state' do
      control = ActiveRecord::QueryRecorder.new { post_graphql(query, current_user: current_user) }

      create_list(:terraform_state_version, 2, terraform_state: create(:terraform_state, project: project))
      create(:terraform_state_version, terraform_state: create(:terraform_state, project: project))

      expect { post_graphql(query, current_user: current_user) }.not_to exceed_query_limit(control)
    end

    context 'when paginating' do
      let(:versions_args) { '(first: 1)' }

      it 'returns a page with a cursor to the next one' do
        expect(state_data['versions']['nodes']).to match([a_graphql_entity_for(latest_version)])
        expect(state_data['versions']['pageInfo']['hasNextPage']).to be(true)
      end
    end
  end

  describe 'versions with independent pagination' do
    let_it_be(:middle_version) do
      create(:terraform_state_version,
        terraform_state: Terraform::State.find(terraform_state.id), version: latest_version.version + 1)
    end

    let_it_be(:newest_version) do
      create(:terraform_state_version,
        terraform_state: Terraform::State.find(terraform_state.id), version: latest_version.version + 2)
    end

    let(:version_fields) { 'nodes { id serial } pageInfo { hasNextPage endCursor }' }
    let(:ordered_aliases) { %w[short long] }
    let(:fields) do
      selections = {
        'short' => "short: versions(first: 1) { #{version_fields} }",
        'long' => "long: versions(first: 3) { #{version_fields} }"
      }

      "terraformStates { nodes { name #{ordered_aliases.map { |name| selections.fetch(name) }.join(' ')} } }"
    end

    let(:query) { graphql_query_for(:project, { fullPath: project.full_path }, fields) }
    let(:state_data) { data['nodes'].find { |node| node['name'] == terraform_state.name } }

    shared_examples 'independently paginated versions' do
      it 'returns each page with its own limit and pagination metadata', :aggregate_failures do
        expect(graphql_errors).to be_nil
        expect(state_data['short']['nodes']).to match([a_graphql_entity_for(newest_version)])
        expect(state_data['short']['pageInfo']['hasNextPage']).to be(true)
        expect(state_data['long']['nodes']).to match([
          a_graphql_entity_for(newest_version),
          a_graphql_entity_for(middle_version),
          a_graphql_entity_for(latest_version)
        ])
        expect(state_data['long']['pageInfo']['hasNextPage']).to be(false)
      end

      it 'continues after the short page without skipping a version', :aggregate_failures do
        cursor = state_data['short']['pageInfo']['endCursor']
        next_page = %(
          terraformStates {
            nodes { name versions(first: 3, after: #{Gitlab::Json.dump(cursor)}) { #{version_fields} } }
          }
        )

        post_graphql(
          graphql_query_for(:project, { fullPath: project.full_path }, next_page), current_user: current_user
        )

        expect(graphql_errors).to be_nil
        next_state = graphql_data.dig('project', 'terraformStates', 'nodes')
          .find { |node| node['name'] == terraform_state.name }
        expect(next_state['versions']['nodes']).to match([
          a_graphql_entity_for(middle_version),
          a_graphql_entity_for(latest_version)
        ])
        expect(next_state['versions']['pageInfo']['hasNextPage']).to be(false)
      end
    end

    include_examples 'independently paginated versions'

    context 'when the larger page is requested first' do
      let(:ordered_aliases) { %w[long short] }

      include_examples 'independently paginated versions'
    end

    it 'isolates an after cursor from another alias with the same page size', :aggregate_failures do
      cursor = state_data['short']['pageInfo']['endCursor']
      fields = %(
        terraformStates {
          nodes {
            name
            next: versions(first: 1, after: #{Gitlab::Json.dump(cursor)}) { #{version_fields} }
            current: versions(first: 1) { #{version_fields} }
          }
        }
      )

      post_graphql(graphql_query_for(:project, { fullPath: project.full_path }, fields), current_user: current_user)

      pages = graphql_data.dig('project', 'terraformStates', 'nodes')
        .find { |node| node['name'] == terraform_state.name }
      expect(graphql_errors).to be_nil
      expect(pages['next']['nodes']).to match([a_graphql_entity_for(middle_version)])
      expect(pages['current']['nodes']).to match([a_graphql_entity_for(newest_version)])
    end

    it 'batches each page across states without a query per state' do
      control = ActiveRecord::QueryRecorder.new { post_graphql(query, current_user: current_user) }

      create_list(:terraform_state_version, 3, terraform_state: create(:terraform_state, project: project))
      create(:terraform_state_version, terraform_state: create(:terraform_state, project: project))

      expect { post_graphql(query, current_user: current_user) }.not_to exceed_query_limit(control)
    end
  end

  describe 'protectionRuleExists' do
    let_it_be(:terraform_state_protection_rule) do
      create(:terraform_state_protection_rule, project: project, state_name: terraform_state.name)
    end

    let(:fields) do
      %(
        terraformStates {
          nodes {
            name
            protectionRuleExists
          }
        }
      )
    end

    let(:query) do
      graphql_query_for(:project, { fullPath: project.full_path }, fields)
    end

    describe 'efficient database queries' do
      let_it_be(:project2) { create(:project) }
      let_it_be(:terraform_states_project2) do
        create_list(:terraform_state, 4, project: project2)
      end

      let_it_be(:terraform_state_protection_rule_project2) do
        create(:terraform_state_protection_rule, project: project2,
          state_name: terraform_states_project2.first.name)
      end

      let_it_be(:user1) { create(:user, maintainer_of: project) }
      let_it_be(:user2) { create(:user, maintainer_of: project2) }

      it 'avoids N+1 database queries' do
        control_count = ActiveRecord::QueryRecorder.new { post_graphql(query, current_user: user1) }

        query2 = graphql_query_for(:project, { fullPath: project2.full_path }, fields)
        expect { post_graphql(query2, current_user: user2) }.not_to exceed_query_limit(control_count)
      end
    end

    context 'when protection rule exists for the terraform state' do
      it 'returns true for protected state and false for unprotected state' do
        unprotected_state = create(:terraform_state, project: project)

        post_graphql(query, current_user: current_user)

        states_data = data['nodes']
        protected_state_data = states_data.find { |s| s['name'] == terraform_state.name }
        unprotected_state_data = states_data.find { |s| s['name'] == unprotected_state.name }

        expect(protected_state_data['protectionRuleExists']).to be true
        expect(unprotected_state_data['protectionRuleExists']).to be false
      end
    end

    context 'when feature flag is disabled' do
      before do
        stub_feature_flags(protected_terraform_states: false)
      end

      it 'returns false for all states' do
        post_graphql(query, current_user: current_user)

        expect(data['nodes']).to all(include('protectionRuleExists' => false))
      end
    end
  end
end
