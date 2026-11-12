# frozen_string_literal: true

require 'spec_helper'

RSpec.describe GitlabSchema.types['ClusterAgentToken'] do
  let(:fields) { %i[cluster_agent created_at created_by_user description id last_used_at name status] }

  it { expect(described_class.graphql_name).to eq('ClusterAgentToken') }

  it { expect(described_class).to require_graphql_authorizations(:read_cluster_agent) }

  it { expect(described_class).to have_graphql_fields(fields) }

  it 'requires read_cluster_agent_token on the project from a granular token', :aggregate_failures do
    directive = described_class.directives.find { |d| d.is_a?(::Directives::Authz::GranularScope) }

    expect(directive.arguments[:permissions]).to eq(%w[read_cluster_agent_token])
    expect(directive.arguments[:boundary_type]).to eq('project')
  end
end
