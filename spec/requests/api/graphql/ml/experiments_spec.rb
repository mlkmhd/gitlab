# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'Query.mlExperiment', feature_category: :mlops do
  include GraphqlHelpers

  let_it_be(:experiment) { create(:ml_experiments) }
  let_it_be(:project) { experiment.project }
  let_it_be(:current_user) { project.owner }
  let_it_be(:candidate) do
    create(:ml_candidates, :with_metrics_and_params, :with_metadata,
      project: project, experiment: experiment)
  end

  let(:user) { current_user }
  let(:boundary_object) { project }
  let(:experiment_selection) { 'id' }
  let(:query) { graphql_query_for(:ml_experiment, { id: global_id_of(experiment) }, experiment_selection) }
  let(:request) { post_graphql(query, token: { personal_access_token: pat }) }
  let(:token) { create(:personal_access_token, user: current_user) }

  context 'when querying project.mlExperiments' do
    let(:experiment_fields) do
      <<~FIELDS
        mlExperiments {
          nodes {
            id
            name
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

    let(:query) { graphql_query_for(:project, { full_path: project.full_path }, experiment_fields) }

    it_behaves_like 'authorizing granular token permissions for GraphQL',
      [:read_project, :read_ml_experiment, :read_ml_flow_run]

    context 'with the getExperiments query of the experiment list page' do
      let(:query) do
        get_graphql_query_as_string('ml/experiment_tracking/graphql/queries/get_experiments.query.graphql')
      end

      def post_query
        post_graphql(query, current_user: current_user, variables: { fullPath: project.full_path })
      end

      def create_experiments(count)
        Array.new(count) do
          create(:ml_experiments, project: project, user: create(:user)).tap do |experiment|
            create_list(:ml_candidates, 2, project: project, experiment: experiment)
          end
        end
      end

      it 'does not run queries per experiment', :aggregate_failures do
        create_experiments(1)
        post_query
        control = ActiveRecord::QueryRecorder.new(skip_cached: false) { post_query }

        create_experiments(2)

        expect { post_query }.not_to exceed_all_query_limit(control)
        expect(graphql_data_at(:project, :ml_experiments, :nodes).size).to eq(4)
      end
    end

    context 'when selecting the candidates of every experiment' do
      let_it_be(:experiments) { [experiment, *create_list(:ml_experiments, 2, project: project)] }

      let(:experiment_fields) do
        <<~FIELDS
          mlExperiments {
            nodes {
              id
              candidates { nodes { id creator { id name webUrl } } }
            }
          }
        FIELDS
      end

      def post_query
        post_graphql(query, token: { personal_access_token: token })
      end

      it 'does not run queries per candidate', :aggregate_failures do
        experiments.each { |record| create_candidates(record, 1) }
        post_query
        control = ActiveRecord::QueryRecorder.new(skip_cached: false) { post_query }

        experiments.each { |record| create_candidates(record, 2) }

        expect { post_query }.not_to exceed_all_query_limit(control)
        expect(graphql_data_at(:project, :ml_experiments, :nodes, :candidates, :nodes).size).to eq(10)
      end
    end
  end

  context 'with the getExperimentCandidates query of the experiment page' do
    let(:query) do
      get_graphql_query_as_string('ml/experiment_tracking/graphql/queries/get_experiment_candidates.query.graphql')
    end

    def post_query
      post_graphql(query, token: { personal_access_token: token }, variables: { id: global_id_of(experiment).to_s })
    end

    where(:created_by_ci_job) { [false, true] }

    with_them do
      it 'does not run queries per candidate', :aggregate_failures do
        create_candidates(experiment, 1, created_by_ci_job: created_by_ci_job)
        post_query
        control = ActiveRecord::QueryRecorder.new(skip_cached: false) { post_query }

        create_candidates(experiment, 2, created_by_ci_job: created_by_ci_job)

        expect { post_query }.not_to exceed_all_query_limit(control)

        nodes = graphql_data_at(:ml_experiment, :candidates, :nodes)
        expect(nodes.size).to eq(4)
        expect(nodes.pluck('ciJob').compact.size).to eq(created_by_ci_job ? 3 : 0)
      end
    end

    context 'when the query selects neither creator nor ciJob' do
      let(:query) { graphql_query_for(:ml_experiment, { id: global_id_of(experiment) }, 'candidates { nodes { id } }') }

      it 'does not load the creators or the CI jobs', :aggregate_failures do
        create_candidates(experiment, 3, created_by_ci_job: true)

        recorder = ActiveRecord::QueryRecorder.new(skip_cached: false) do
          post_graphql(query, token: { personal_access_token: token })
        end

        expect(graphql_data_at(:ml_experiment, :candidates, :nodes).size).to eq(4)
        expect(recorder.log).not_to include(a_string_matching(/FROM "p_ci_builds"/))
        expect(recorder.log).not_to include(a_string_matching(/FROM "users" WHERE "users"."id" IN/))
      end
    end
  end

  context 'when the token is scoped to the experiment but not to its candidates' do
    let(:pat) do
      create(:granular_pat, user: user, boundary: ::Authz::Boundary.for(project),
        permissions: %w[read_ml_experiment])
    end

    let(:experiment_selection) { 'id candidates { nodes { id } }' }

    it 'returns the experiment without its candidates', :aggregate_failures do
      request

      expect(graphql_data_at(:ml_experiment, :id)).to be_present
      expect(graphql_data_at(:ml_experiment, :candidates, :nodes)).to all(be_nil)
    end
  end

  context 'when selecting metrics, params or metadata of several candidates' do
    let_it_be(:other_candidate) do
      create(:ml_candidates, :with_metrics_and_params, :with_metadata, project: project, experiment: experiment)
    end

    let(:experiment_selection) { "candidates { nodes { id #{field} { nodes { id } } } }" }
    let(:child_ids_by_candidate) do
      [candidate, other_candidate].to_h do |record|
        [global_id_of(record).to_s, record.public_send(field).map { |child| global_id_of(child).to_s }]
      end
    end

    where(:field, :table) do
      [
        %w[metrics ml_candidate_metrics],
        %w[params ml_candidate_params],
        %w[metadata ml_candidate_metadata]
      ]
    end

    with_them do
      it 'resolves the field for one candidate only', :aggregate_failures do
        recorder = ActiveRecord::QueryRecorder.new { post_graphql(query, current_user: current_user) }

        expect(graphql_errors.pluck('message'))
          .to eq(["\"#{field}\" field can be requested only for 1 MlCandidate(s) at a time."])
        expect(recorder.log.grep(/FROM "#{table}"/).size).to eq(1)

        nodes = graphql_data_at(:ml_experiment, :candidates, :nodes)
        resolved_nodes = nodes.compact

        expect(nodes.size).to eq(2)
        expect(resolved_nodes.size).to eq(1)
        expect(resolved_nodes.first.dig(field, 'nodes').pluck('id'))
          .to match_array(child_ids_by_candidate[resolved_nodes.first['id']])
      end

      context 'when the limit_ml_candidate_graphql_fields feature flag is disabled' do
        before do
          stub_feature_flags(limit_ml_candidate_graphql_fields: false)
        end

        it 'resolves the field for every candidate', :aggregate_failures do
          post_graphql(query, current_user: current_user)

          expect(graphql_errors).to be_nil
          expect(graphql_data_at(:ml_experiment, :candidates, :nodes, field, :nodes, :id)).to match_array(
            [candidate, other_candidate].flat_map(&field.to_sym).map { |record| global_id_of(record).to_s }
          )
        end
      end
    end

    context 'when the limit_ml_candidate_graphql_fields feature flag is enabled for one project only' do
      let_it_be(:other_project) { create(:project) }

      let(:field) { 'metrics' }

      it 'applies the limit when the flag is enabled for the project of the candidates' do
        stub_feature_flags(limit_ml_candidate_graphql_fields: project)

        post_graphql(query, current_user: current_user)

        expect(graphql_errors.pluck('message'))
          .to eq(['"metrics" field can be requested only for 1 MlCandidate(s) at a time.'])
      end

      it 'does not apply the limit when the flag is enabled for another project' do
        stub_feature_flags(limit_ml_candidate_graphql_fields: other_project)

        post_graphql(query, current_user: current_user)

        expect(graphql_errors).to be_nil
      end
    end
  end

  it_behaves_like 'authorizing granular token permissions for GraphQL with a skipped child type',
    [:read_ml_experiment, :read_ml_flow_run] do
    let(:experiment_selection) { 'candidates { nodes { _links { showPath artifactPath } } }' }
    let(:skipped_data_path) { %i[ml_experiment candidates nodes _links] }
  end

  it_behaves_like 'authorizing granular token permissions for GraphQL with a skipped child type',
    [:read_ml_experiment, :read_ml_flow_run] do
    let(:experiment_selection) { 'candidates { nodes { metrics { nodes { id name } } } }' }
    let(:skipped_data_path) { %i[ml_experiment candidates nodes metrics nodes] }
  end

  it_behaves_like 'authorizing granular token permissions for GraphQL with a skipped child type',
    [:read_ml_experiment, :read_ml_flow_run] do
    let(:experiment_selection) { 'candidates { nodes { params { nodes { id name } } } }' }
    let(:skipped_data_path) { %i[ml_experiment candidates nodes params nodes] }
  end

  it_behaves_like 'authorizing granular token permissions for GraphQL with a skipped child type',
    [:read_ml_experiment, :read_ml_flow_run] do
    let(:experiment_selection) { 'candidates { nodes { metadata { nodes { id name } } } }' }
    let(:skipped_data_path) { %i[ml_experiment candidates nodes metadata nodes] }
  end

  def create_candidates(experiment, count, created_by_ci_job: false)
    Array.new(count) do
      ci_build = create(:ci_build, project: project, user: create(:user)) if created_by_ci_job

      create(:ml_candidates, project: project, experiment: experiment, user: create(:user), ci_build: ci_build)
    end
  end
end
