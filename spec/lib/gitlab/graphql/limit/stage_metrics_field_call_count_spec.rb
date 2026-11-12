# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Gitlab::Graphql::Limit::StageMetricsFieldCallCount, feature_category: :value_stream_management do
  include GraphqlHelpers

  let_it_be(:group) { create(:group) }
  let_it_be(:project) { create(:project, group: group) }

  let(:stage) { build_stubbed(:cycle_analytics_stage, namespace: project.project_namespace) }
  let(:owner) { fresh_object_type }
  let(:field) do
    ::Types::BaseField.new(name: 'name', type: GraphQL::Types::String, null: true, owner: owner) do
      extension(::Gitlab::Graphql::Limit::StageMetricsFieldCallCount, limit: 1)
    end
  end

  let(:query) { GraphQL::Query.new(GitlabSchema) }

  def resolve_name
    resolve_field(field, stage, object_type: owner, query: query)
  end

  it 'returns an error when the field is called more often than the limit' do
    expect(resolve_name).to eq(stage.name)
    expect(resolve_name).to be_an_instance_of(Gitlab::Graphql::Errors::LimitError)
  end

  context 'when the vsa_stage_metrics_validate_timeframe feature flag is enabled for another group' do
    before do
      stub_feature_flags(vsa_stage_metrics_validate_timeframe: create(:group))
    end

    it 'does not limit the calls' do
      resolve_name

      expect(resolve_name).to eq(stage.name)
    end
  end
end
