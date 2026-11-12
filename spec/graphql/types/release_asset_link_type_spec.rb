# frozen_string_literal: true

require 'spec_helper'

RSpec.describe GitlabSchema.types['ReleaseAssetLink'] do
  it { expect(described_class).to require_graphql_authorizations(:read_release) }

  it 'skips granular token authorization because the parent authorizes' do
    directive = described_class.directives.find { |d| d.is_a?(::Directives::Authz::GranularScope) }

    expect(directive.arguments[:skip_reason]).to eq('parent_authorizes')
    expect(directive.arguments[:parent_authorizes]).to eq(%w[read_release])
  end

  it 'has the expected fields' do
    expected_fields = %w[
      id name url link_type direct_asset_url direct_asset_path
    ]

    expect(described_class).to include_graphql_fields(*expected_fields)
  end
end
