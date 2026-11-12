# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'Query.project.newMergeRequestPipelines', feature_category: :continuous_integration do
  include GraphqlHelpers
  include ProjectForksHelper

  let_it_be(:project) { create(:project, :private, :repository) }
  let_it_be(:developer) { create(:user, developer_of: project) }

  let(:current_user) { developer }
  let(:source_project) { project }
  let(:arguments) { { source_branch: 'fix', target_branch: 'master' } }

  let(:query) do
    graphql_query_for(
      :project, { full_path: source_project.full_path },
      query_graphql_field(:new_merge_request_pipelines, arguments, 'count nodes { id }')
    )
  end

  let(:pipelines_data) { graphql_data_at(:project, :new_merge_request_pipelines) }

  def compare_shas(source, target, target_branch: 'master')
    MergeRequests::BuildService
      .new(
        project: source, current_user: current_user,
        params: { source_branch: 'fix', target_project: target, target_branch: target_branch }
      )
      .execute
      .commit_shas
  end

  context 'with branch pipelines on the commits of the compare' do
    let_it_be(:shas) do
      MergeRequests::BuildService
        .new(project: project, current_user: developer, params: { source_branch: 'fix', target_branch: 'master' })
        .execute
        .commit_shas
    end

    let_it_be(:head_pipeline) { create(:ci_pipeline, source: :push, project: project, ref: 'fix', sha: shas.first) }
    let_it_be(:older_pipeline) { create(:ci_pipeline, source: :push, project: project, ref: 'fix', sha: shas.last) }

    before_all do
      create(:ci_pipeline, source: :push, project: project, ref: 'other-branch', sha: shas.first)
      create(:ci_pipeline, source: :push, project: project, ref: 'v1.0.0', tag: true, sha: shas.first)
      create(:ci_pipeline, source: :push, project: project, ref: 'fix', sha: project.commit('master').sha)
    end

    it 'returns the branch pipelines of the source branch for every commit, newest first' do
      expect(shas.size).to be > 1

      post_graphql(query, current_user: current_user)

      expect(pipelines_data['count']).to eq(2)
      expect(graphql_dig_at(pipelines_data, :nodes, :id)).to eq(
        [older_pipeline, head_pipeline].map { |pipeline| pipeline.to_global_id.to_s }
      )
    end

    context 'when the user cannot create a merge request from the project' do
      let(:current_user) { create(:user, guest_of: project) }

      it 'returns null' do
        post_graphql(query, current_user: current_user)

        expect(pipelines_data).to be_nil
      end
    end

    context 'when the field is requested for two projects' do
      let_it_be(:other_project) { create(:project, :repository, developers: developer) }

      let(:query) do
        graphql_query_for(
          :projects, { full_paths: [project.full_path, other_project.full_path] },
          "nodes { #{query_graphql_field(:new_merge_request_pipelines, arguments, 'count')} }"
        )
      end

      it 'returns an error' do
        post_graphql(query, current_user: current_user)

        expect_graphql_errors_to_include(
          /"newMergeRequestPipelines" field can be requested only for 1 Project\(s\) at a time/
        )
      end
    end
  end

  context 'with a merge request from a fork' do
    let_it_be(:fork) { fork_project(project, developer, repository: true) }

    let(:source_project) { fork }

    before_all do
      fork.repository.add_branch(developer, 'fork-only', 'master')
    end

    context 'when the target is the upstream project' do
      let(:arguments) { { source_branch: 'fix', target_branch: 'master', target_project_path: project.full_path } }

      let!(:fork_pipeline) do
        create(:ci_pipeline, source: :push, project: fork, ref: 'fix', sha: compare_shas(fork, project).first)
      end

      it 'returns the branch pipelines of the fork' do
        post_graphql(query, current_user: current_user)

        expect(graphql_dig_at(pipelines_data, :nodes, :id)).to contain_exactly(fork_pipeline.to_global_id.to_s)
      end
    end

    # The default target is upstream, which has no `fork-only` branch.
    context 'when the target is the fork itself' do
      let(:arguments) { { source_branch: 'fix', target_branch: 'fork-only', target_project_path: fork.full_path } }

      let!(:fork_pipeline) do
        sha = compare_shas(fork, fork, target_branch: 'fork-only').first
        create(:ci_pipeline, source: :push, project: fork, ref: 'fix', sha: sha)
      end

      it 'compares against the target project of targetProjectPath' do
        post_graphql(query, current_user: current_user)

        expect(graphql_dig_at(pipelines_data, :nodes, :id)).to contain_exactly(fork_pipeline.to_global_id.to_s)
      end
    end
  end

  context 'with a granular personal access token' do
    let(:user) { developer }
    let(:boundary_object) { project }
    let(:request) { post_graphql(query, token: { personal_access_token: pat }) }

    it_behaves_like 'authorizing granular token permissions for GraphQL', [:read_project, :read_pipeline]

    context 'when the token can read the project but not its pipelines' do
      let(:pat) do
        assignable = ::Authz::PermissionGroups::Assignable.for_permission(:read_project).min_by(&:name).name
        create(:granular_pat, user: user, boundary: ::Authz::Boundary.for(project), permissions: [assignable])
      end

      before_all do
        create(:ci_pipeline, source: :push, project: project, ref: 'fix', sha: project.commit('fix').id)
      end

      # PipelineType alone hides the nodes but not the count.
      it 'returns the project without the field', :aggregate_failures do
        request

        expect(graphql_errors).to be_nil
        expect(graphql_data_at(:project)).to be_present
        expect(pipelines_data).to be_nil
      end
    end
  end
end
