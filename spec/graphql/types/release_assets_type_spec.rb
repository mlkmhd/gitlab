# frozen_string_literal: true

require 'spec_helper'

RSpec.describe GitlabSchema.types['ReleaseAssets'] do
  it { expect(described_class).to require_graphql_authorizations(:read_release) }

  it 'skips granular token authorization because the parent authorizes' do
    directive = described_class.directives.find { |d| d.is_a?(::Directives::Authz::GranularScope) }

    expect(directive.arguments[:skip_reason]).to eq('parent_authorizes')
    expect(directive.arguments[:parent_authorizes]).to eq(%w[read_release])
  end

  it 'has the expected fields' do
    expected_fields = %w[
      count links sources
    ]

    expect(described_class).to include_graphql_fields(*expected_fields)
  end

  describe 'links field' do
    subject { described_class.fields['links'] }

    it { is_expected.to have_graphql_type(Types::ReleaseAssetLinkType.connection_type) }
  end

  describe 'sources field' do
    subject { described_class.fields['sources'] }

    it { is_expected.to have_graphql_type(Types::ReleaseSourceType.connection_type) }
  end
end
