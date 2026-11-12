# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Gitlab::Graphql::Limit::MlCandidateFieldCallCount, feature_category: :mlops do
  include GraphqlHelpers

  let(:project) { build_stubbed(:project) }
  let(:candidate) { build_stubbed(:ml_candidates, project: project) }
  let(:owner) { fresh_object_type }
  let(:field) do
    ::Types::BaseField.new(name: 'name', type: GraphQL::Types::String, null: true, owner: owner) do
      extension(::Gitlab::Graphql::Limit::MlCandidateFieldCallCount, limit: 1)
    end
  end

  let(:query) { GraphQL::Query.new(GitlabSchema) }

  def resolve_name
    resolve_field(field, candidate, object_type: owner, query: query)
  end

  it 'returns an error when the field is called more often than the limit' do
    expect(resolve_name).to eq(candidate.name)
    expect(resolve_name).to be_an_instance_of(Gitlab::Graphql::Errors::LimitError)
  end

  context 'when the limit_ml_candidate_graphql_fields feature flag is enabled for another project' do
    before do
      stub_feature_flags(limit_ml_candidate_graphql_fields: build_stubbed(:project))
    end

    it 'does not limit the calls' do
      resolve_name

      expect(resolve_name).to eq(candidate.name)
    end
  end
end
