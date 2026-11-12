# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'Query.mlModel', feature_category: :mlops do
  include GraphqlHelpers

  let_it_be(:model) { create(:ml_models, :with_versions) }
  let_it_be(:project) { model.project }
  let_it_be(:current_user) { project.owner }
  let_it_be(:candidate) do
    create(:ml_candidates, :with_metrics_and_params, :with_metadata,
      project: project, experiment: model.default_experiment)
  end

  let(:user) { current_user }
  let(:boundary_object) { project }
  let(:model_selection) { 'id' }
  let(:query) { graphql_query_for(:ml_model, { id: global_id_of(model) }, model_selection) }
  let(:request) { post_graphql(query, token: { personal_access_token: pat }) }

  context 'when querying project.mlModels' do
    let(:model_fields) do
      <<~FIELDS
        mlModels {
          nodes {
            id
            name
            _links { showPath }
            latestVersion {
              id
              _links { showPath packagePath importPath }
            }
            candidates {
              nodes {
                id
                _links { showPath artifactPath }
                params { nodes { id name } }
                metrics { nodes { id name } }
                metadata { nodes { id name } }
              }
            }
          }
        }
      FIELDS
    end

    let(:query) { graphql_query_for(:project, { full_path: project.full_path }, model_fields) }

    it_behaves_like 'authorizing granular token permissions for GraphQL',
      [:read_project, :read_ml_model, :read_model_version, :read_ml_flow_run]

    context 'with the getModels query of the model registry list' do
      # A project of its own, so that every listed model has the shape that create_models builds.
      let_it_be(:list_project) { create(:project, namespace: current_user.namespace) }
      let_it_be(:token) { create(:personal_access_token, user: current_user) }

      let(:query) { get_graphql_query_as_string('ml/model_registry/graphql/queries/get_models.query.graphql') }

      def post_query
        post_graphql(query, token: { personal_access_token: token }, variables: { fullPath: list_project.full_path })
      end

      def create_models(count)
        Array.new(count) do
          create(:ml_models, :with_latest_version_and_package, project: list_project, user: create(:user))
        end
      end

      it 'does not run queries per model', :aggregate_failures do
        create_models(1)
        post_query
        control = ActiveRecord::QueryRecorder.new(skip_cached: false) { post_query }

        create_models(2)

        expect { post_query }.not_to exceed_all_query_limit(control)

        nodes = graphql_data_at(:project, :ml_models, :nodes)
        expect(nodes.size).to eq(3)
        expect(nodes.pluck('author').compact.size).to eq(3)
        expect(nodes.pluck('latestVersion').compact.size).to eq(3)
      end
    end
  end

  context 'when the token is scoped to the model but not to its children' do
    let(:pat) do
      create(:granular_pat, user: user, boundary: ::Authz::Boundary.for(project), permissions: %w[read_ml_model])
    end

    let(:model_selection) { 'id latestVersion { id } candidates { nodes { id } }' }

    it 'returns the model without its versions or candidates', :aggregate_failures do
      request

      expect(graphql_data_at(:ml_model, :id)).to be_present
      expect(graphql_data_at(:ml_model, :latest_version)).to be_nil
      expect(graphql_data_at(:ml_model, :candidates, :nodes)).to all(be_nil)
    end
  end

  context 'when selecting candidate metrics, params and metadata' do
    let_it_be(:registry_model) { create(:ml_models, project: project) }
    let_it_be(:model_versions) { create_list(:ml_model_versions, 2, :with_package, model: registry_model) }
    let_it_be(:version_candidates) do
      model_versions.map do |version|
        version.candidate.tap do |version_candidate|
          create(:ml_candidate_metrics, candidate: version_candidate)
          create(:ml_candidate_params, candidate: version_candidate)
          create(:ml_candidate_metadata, candidate: version_candidate)
        end
      end
    end

    let(:model_version) { registry_model.latest_version }

    def expect_candidate_children(candidate_data, candidate)
      %w[metrics params metadata].each do |field|
        expect(candidate_data.dig(field, 'nodes').pluck('id'))
          .to match_array(candidate.public_send(field).map { |record| global_id_of(record).to_s })
      end
    end

    context 'with the getModel query of the model detail page' do
      let(:query) { get_graphql_query_as_string('ml/model_registry/graphql/queries/get_model.query.graphql') }

      it 'resolves them for the candidate of the latest version', :aggregate_failures do
        post_graphql(query, current_user: current_user, variables: { id: global_id_of(registry_model).to_s })

        expect(graphql_errors).to be_nil
        expect_candidate_children(graphql_data_at(:ml_model, :latest_version, :candidate), model_version.candidate)
      end
    end

    context 'with the getModelVersion query of the model version detail page' do
      let(:query) do
        get_graphql_query_as_string('ml/model_registry/graphql/queries/get_model_version.query.graphql')
      end

      it 'resolves them for the candidate of the version', :aggregate_failures do
        post_graphql(query, current_user: current_user,
          variables: { modelId: global_id_of(registry_model).to_s, modelVersionId: global_id_of(model_version).to_s })

        expect(graphql_errors).to be_nil
        expect_candidate_children(graphql_data_at(:ml_model, :version, :candidate), model_version.candidate)
      end
    end

    context 'with the candidates of several versions' do
      let(:query) do
        graphql_query_for(:ml_model, { id: global_id_of(registry_model) },
          "versions { nodes { version candidate { id #{field} { nodes { id } } } } }")
      end

      let(:child_ids_by_candidate) do
        version_candidates.to_h do |record|
          [global_id_of(record).to_s, record.public_send(field).map { |child| global_id_of(child).to_s }]
        end
      end

      where(:field) { %w[metrics params metadata] }

      with_them do
        it 'resolves the field for one candidate only', :aggregate_failures do
          post_graphql(query, current_user: current_user)

          expect(graphql_errors.pluck('message'))
            .to eq(["\"#{field}\" field can be requested only for 1 MlCandidate(s) at a time."])

          nodes = graphql_data_at(:ml_model, :versions, :nodes)
          resolved_nodes = nodes.compact

          expect(nodes.size).to eq(2)
          expect(resolved_nodes.size).to eq(1)
          expect(resolved_nodes.first.dig('candidate', field, 'nodes').pluck('id'))
            .to match_array(child_ids_by_candidate[resolved_nodes.first.dig('candidate', 'id')])
        end

        context 'when the limit_ml_candidate_graphql_fields feature flag is disabled' do
          before do
            stub_feature_flags(limit_ml_candidate_graphql_fields: false)
          end

          it 'resolves the field for every candidate', :aggregate_failures do
            post_graphql(query, current_user: current_user)

            expect(graphql_errors).to be_nil
            expect(graphql_data_at(:ml_model, :versions, :nodes, :candidate, field, :nodes, :id)).to match_array(
              version_candidates.flat_map(&field.to_sym).map { |record| global_id_of(record).to_s }
            )
          end
        end
      end
    end
  end

  context 'with the getModelCandidates query of the model page' do
    let_it_be(:token) { create(:personal_access_token, user: current_user) }

    let(:query) { get_graphql_query_as_string('ml/model_registry/graphql/queries/get_model_candidates.query.graphql') }

    def post_query
      post_graphql(query, token: { personal_access_token: token }, variables: { id: global_id_of(model).to_s })
    end

    def create_candidates(count, created_by_ci_job:)
      Array.new(count) do
        ci_build = create(:ci_build, project: project, user: create(:user)) if created_by_ci_job

        create(:ml_candidates, project: project, experiment: model.default_experiment, user: create(:user),
          ci_build: ci_build)
      end
    end

    where(:created_by_ci_job) { [false, true] }

    with_them do
      it 'does not run queries per candidate', :aggregate_failures do
        create_candidates(1, created_by_ci_job: created_by_ci_job)
        post_query
        control = ActiveRecord::QueryRecorder.new(skip_cached: false) { post_query }

        create_candidates(2, created_by_ci_job: created_by_ci_job)

        expect { post_query }.not_to exceed_all_query_limit(control)

        nodes = graphql_data_at(:ml_model, :candidates, :nodes)
        expect(nodes.size).to eq(4)
        expect(nodes.pluck('ciJob').compact.size).to eq(created_by_ci_job ? 3 : 0)
      end
    end
  end

  it_behaves_like 'authorizing granular token permissions for GraphQL with a skipped child type',
    [:read_ml_model] do
    let(:model_selection) { '_links { showPath }' }
    let(:skipped_data_path) { %i[ml_model _links] }
  end

  it_behaves_like 'authorizing granular token permissions for GraphQL with a skipped child type',
    [:read_ml_model, :read_model_version] do
    let(:model_selection) { 'latestVersion { _links { showPath packagePath importPath } }' }
    let(:skipped_data_path) { %i[ml_model latest_version _links] }
  end

  it_behaves_like 'authorizing granular token permissions for GraphQL with a skipped child type',
    [:read_ml_model, :read_ml_flow_run] do
    let(:model_selection) { 'candidates { nodes { _links { showPath artifactPath } } }' }
    let(:skipped_data_path) { %i[ml_model candidates nodes _links] }
  end

  it_behaves_like 'authorizing granular token permissions for GraphQL with a skipped child type',
    [:read_ml_model, :read_ml_flow_run] do
    let(:model_selection) { 'candidates { nodes { metrics { nodes { id name } } } }' }
    let(:skipped_data_path) { %i[ml_model candidates nodes metrics nodes] }
  end

  it_behaves_like 'authorizing granular token permissions for GraphQL with a skipped child type',
    [:read_ml_model, :read_ml_flow_run] do
    let(:model_selection) { 'candidates { nodes { params { nodes { id name } } } }' }
    let(:skipped_data_path) { %i[ml_model candidates nodes params nodes] }
  end

  it_behaves_like 'authorizing granular token permissions for GraphQL with a skipped child type',
    [:read_ml_model, :read_ml_flow_run] do
    let(:model_selection) { 'candidates { nodes { metadata { nodes { id name } } } }' }
    let(:skipped_data_path) { %i[ml_model candidates nodes metadata nodes] }
  end
end
