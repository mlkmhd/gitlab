# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'Project Deployment query', feature_category: :continuous_delivery do
  include GraphqlHelpers

  let_it_be(:project) { create(:project, :private, :repository) }
  let_it_be(:developer) { create(:user, developer_of: project) }
  let_it_be(:guest) { create(:user, guest_of: project) }
  let_it_be(:environment) { create(:environment, project: project) }
  let_it_be(:deployment) { create(:deployment, environment: environment, project: project) }

  let(:user) { developer }

  let(:query) do
    %(
      query {
        project(fullPath: "#{project.full_path}") {
          deployment(iid: #{deployment.iid}) {
            id
            iid
            ref
            tag
            sha
            createdAt
            updatedAt
            finishedAt
            status
          }
        }
      }
    )
  end

  subject { GitlabSchema.execute(query, context: { current_user: user }).as_json }

  it 'returns the deployment of the project' do
    deployment_data = subject.dig('data', 'project', 'deployment')

    expect(deployment_data['iid']).to eq(deployment.iid.to_s)
  end

  context 'when user is guest' do
    let(:user) { guest }

    it 'returns nothing' do
      deployment_data = subject.dig('data', 'project', 'deployment')

      expect(deployment_data).to be_nil
    end
  end

  context 'with a fine-grained personal access token' do
    using RSpec::Parameterized::TableSyntax

    let_it_be(:tagged_deployment) do
      create(:deployment, :success, environment: environment, project: project, ref: 'v1.1.0', tag: true,
        sha: project.repository.find_tag('v1.1.0').dereferenced_target.sha)
    end

    let(:boundary_object) { project }
    let(:deployment_fields) { 'iid' }
    let(:request) do
      post_graphql(
        graphql_query_for(:project, { full_path: project.full_path },
          query_graphql_field(:deployment, { iid: tagged_deployment.iid.to_s }, deployment_fields)),
        token: { personal_access_token: pat }
      )
    end

    it_behaves_like 'authorizing granular token permissions for GraphQL', [:read_project, :read_deployment]

    it_behaves_like 'denying a granular token that only authorizes the parent of a field', :read_project do
      let(:parent_data_path) { %i[project] }
      let(:field_data_path) { %i[project deployment] }
    end

    it_behaves_like 'authorizing granular token permissions for GraphQL with a skipped child type',
      [:read_project, :read_deployment] do
      let(:deployment_fields) { 'tags { name }' }
      let(:skipped_data_path) { [:project, :deployment, :tags, 0, :name] }
    end

    it_behaves_like 'authorizing granular token permissions for GraphQL with a skipped child type',
      [:read_project, :read_deployment] do
      let(:deployment_fields) { 'userPermissions { destroyDeployment }' }
      let(:skipped_data_path) { [:project, :deployment, :user_permissions] }
    end

    context 'when the token reads the deployments of an environment' do
      let(:pat) do
        create(:granular_pat, user: user, boundary: ::Authz::Boundary.for(project),
          permissions: %w[read_project read_environment read_deployment])
      end

      it 'returns the deployments', :aggregate_failures do
        post_graphql(
          graphql_query_for(:project, { full_path: project.full_path },
            query_graphql_field(:environment, { name: environment.name },
              'deployments { nodes { iid } } lastDeployment(status: SUCCESS) { iid }')),
          token: { personal_access_token: pat }
        )

        expect(graphql_errors).to be_nil
        expect(graphql_data_at(:project, :environment, :deployments, :nodes, :iid))
          .to contain_exactly(deployment.iid.to_s, tagged_deployment.iid.to_s)
        expect(graphql_data_at(:project, :environment, :last_deployment, :iid)).to eq(tagged_deployment.iid.to_s)
      end
    end
  end
end
