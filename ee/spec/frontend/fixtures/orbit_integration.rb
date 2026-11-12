# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'Orbit Integration (GraphQL fixtures)', type: :request, feature_category: :knowledge_graph do
  include ApiHelpers
  include GraphqlHelpers
  include JavaScriptFixturesHelpers

  let_it_be(:owner) { create(:user) }
  let_it_be(:group) { create(:group, :private, name: 'orbit-fixtures', path: 'orbit-fixtures', owners: owner) }

  let(:grpc_client) { instance_double(Analytics::KnowledgeGraph::GrpcClient) }
  let(:indexing_phase) { 'ready' }

  base_output_path = 'graphql/orbit/integration/'

  before do
    stub_config(knowledge_graph: { 'enabled' => true })
    stub_licensed_features(orbit: true)
    stub_feature_flags(orbit_trial: false, orbit_promo_access_gate: false)

    allow(Analytics::KnowledgeGraph::GrpcClient).to receive(:new).and_return(grpc_client)
    allow(grpc_client).to receive(:get_indexing_status) do |traversal_paths:, **|
      { statuses: traversal_paths.map { |path| { traversal_path: path, phase: indexing_phase, domains: [] } } }
    end

    sign_in(owner)
  end

  describe GraphQL::Query do
    let(:settings_query) { get_graphql_query_as_string('orbit/graphql/queries/group_settings.query.graphql', ee: true) }
    let(:update_mutation) do
      get_graphql_query_as_string('orbit/graphql/mutations/orbit_update.mutation.graphql', ee: true)
    end

    def post_settings
      post_graphql(settings_query, current_user: owner, variables: { fullPath: group.full_path })

      expect_graphql_errors_to_be_empty
    end

    it "#{base_output_path}get_orbit_group_settings.query.graphql.json" do
      post_settings

      expect(graphql_data_at(:group, :orbit, :enabled)).to be(false)
      expect(graphql_data_at(:group, :orbit, :access, :turn_on_denial_reason)).to be_nil
    end

    context 'when Orbit is on' do
      before do
        create(:knowledge_graph_enabled_namespace, namespace: group)
      end

      it "#{base_output_path}get_orbit_group_settings_ready.query.graphql.json" do
        post_settings

        expect(graphql_data_at(:group, :orbit, :indexing, :state)).to eq('READY')
      end

      context 'when indexing is in progress' do
        let(:indexing_phase) { 'syncing' }

        it "#{base_output_path}get_orbit_group_settings_indexing.query.graphql.json" do
          post_settings

          expect(graphql_data_at(:group, :orbit, :indexing, :state)).to eq('INDEXING')
        end
      end
    end

    context 'when the trial has ended', :saas do
      before do
        stub_feature_flags(orbit_trial: group)
        allow(Gitlab::SubscriptionPortal::Client).to receive(:product_trial).and_return(
          Gitlab::SubscriptionPortal::ProductTrialResponse.new(state: :expired, trial_expires_at: Time.utc(2015, 6, 30))
        )
      end

      it "#{base_output_path}get_orbit_group_settings_trial_ended.query.graphql.json" do
        post_settings

        expect(graphql_data_at(:group, :orbit, :access, :state)).to eq('TRIAL_ENDED')
      end
    end

    it "#{base_output_path}orbit_update.mutation.graphql.json" do
      post_graphql(update_mutation, current_user: owner,
        variables: { input: { groupPath: group.full_path, enabled: true } })

      expect_graphql_errors_to_be_empty
      expect(graphql_data_at(:orbit_update, :group, :orbit, :enabled)).to be(true)
    end

    it "#{base_output_path}orbit_update_error.mutation.graphql.json" do
      allow_next_instance_of(Analytics::KnowledgeGraph::ToggleNamespaceService) do |service|
        allow(service).to receive(:execute)
          .and_return(ServiceResponse.error(message: 'GitLab Orbit could not be turned on for this group.'))
      end

      post_graphql(update_mutation, current_user: owner,
        variables: { input: { groupPath: group.full_path, enabled: true } })

      expect_graphql_errors_to_be_empty
      expect(graphql_data_at(:orbit_update, :group)).to be_nil
    end
  end
end
