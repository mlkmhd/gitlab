# frozen_string_literal: true

require 'spec_helper'

RSpec.describe GitlabSchema.types['AgentConfiguration'], feature_category: :deployment_management do
  let(:fields) { %i[agent_name] }

  it { expect(described_class.graphql_name).to eq('AgentConfiguration') }
  it { expect(described_class.description).to eq('Configuration details for an Agent') }
  it { expect(described_class).to have_graphql_fields(fields) }

  it 'skips granular token authorization because the parent authorizes' do
    directive = described_class.directives.find { |d| d.is_a?(::Directives::Authz::GranularScope) }

    expect(directive.arguments[:skip_reason]).to eq('parent_authorizes')
    expect(directive.arguments[:parent_authorizes]).to eq(%w[read_cluster_agent])
  end
end
