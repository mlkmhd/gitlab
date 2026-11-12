# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Types::Kas::AgentVersionWarningType, feature_category: :deployment_management do
  include GraphqlHelpers

  let(:fields) { %i[message type] }

  it { expect(described_class.graphql_name).to eq('AgentVersionWarning') }
  it { expect(described_class.description).to eq('Version-related warning for a connected Agent') }
  it { expect(described_class).to have_graphql_fields(fields) }

  it 'skips granular token authorization because the parent authorizes' do
    directive = described_class.directives.find { |d| d.is_a?(::Directives::Authz::GranularScope) }

    expect(directive.arguments[:skip_reason]).to eq('parent_authorizes')
    expect(directive.arguments[:parent_authorizes]).to eq(%w[read_cluster_agent])
  end
end
