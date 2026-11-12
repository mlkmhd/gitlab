# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Mutations::Vulnerabilities::LinkMergeRequest, feature_category: :vulnerability_management do
  include GraphqlHelpers

  let_it_be(:project) { create(:project) }
  let_it_be(:current_user) { create(:user, maintainer_of: project) }
  let_it_be(:merge_request) { create(:merge_request, source_project: project) }
  let_it_be(:vulnerability) { create(:vulnerability, :with_findings, project: project) }

  let(:scope_validator) { nil }
  let(:query) { GraphQL::Query.new(empty_schema, document: nil, context: {}, variables: {}) }
  let(:query_context) do
    GraphQL::Query::Context.new(
      query: query,
      values: { current_user: current_user, scope_validator: scope_validator }
    )
  end

  let(:mutation) { described_class.new(object: nil, context: query_context, field: nil) }

  subject(:resolve) do
    mutation.resolve(
      vulnerability_id: GitlabSchema.id_from_object(vulnerability),
      merge_request_id: GitlabSchema.id_from_object(merge_request)
    )
  end

  before do
    stub_licensed_features(security_dashboard: true)
  end

  describe '#resolve' do
    shared_examples 'creates the link with source' do |expected_source|
      it "passes source #{expected_source} to the create service" do
        expect(::VulnerabilityMergeRequestLinks::CreateService).to receive(:new).with(
          hash_including(params: hash_including(source: expected_source))
        ).and_call_original

        expect(resolve[:errors]).to be_empty
      end
    end

    context 'without a scope validator' do
      it_behaves_like 'creates the link with source', :unknown
    end

    context 'when the request is not an AI workflow request' do
      let(:scope_validator) do
        instance_double(Gitlab::Auth::ScopeValidator, valid_for?: true, ai_workflow_request?: false)
      end

      it_behaves_like 'creates the link with source', :unknown
    end

    context 'when the request is an AI workflow request' do
      let(:scope_validator) do
        instance_double(Gitlab::Auth::ScopeValidator, valid_for?: true, ai_workflow_request?: true)
      end

      it_behaves_like 'creates the link with source', :ai_workflow
    end
  end
end
