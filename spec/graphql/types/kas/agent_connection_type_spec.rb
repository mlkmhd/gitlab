# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Types::Kas::AgentConnectionType do
  include GraphqlHelpers

  let(:fields) { %i[connected_at connection_id metadata warnings] }

  it { expect(described_class.graphql_name).to eq('ConnectedAgent') }
  it { expect(described_class.description).to eq('Connection details for an Agent') }
  it { expect(described_class).to have_graphql_fields(fields) }

  it 'skips granular token authorization because the parent authorizes' do
    directive = described_class.directives.find { |d| d.is_a?(::Directives::Authz::GranularScope) }

    expect(directive.arguments[:skip_reason]).to eq('parent_authorizes')
    expect(directive.arguments[:parent_authorizes]).to eq(%w[read_cluster_agent])
  end

  describe '#connected_at' do
    let(:connected_at) { double(Google::Protobuf::Timestamp, seconds: 123456, nanos: 654321) }
    let(:object) { double(Gitlab::Agent::AgentTracker::Rpc::ConnectedAgentk, connected_at: connected_at) }

    it 'converts the seconds value to a timestamp' do
      expect(resolve_field(:connected_at, object)).to eq(Time.at(connected_at.seconds))
    end
  end
end
