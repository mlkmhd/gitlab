# frozen_string_literal: true

require 'spec_helper'

RSpec.describe GitlabSchema.types['FeatureFlag'], feature_category: :feature_flags do
  specify { expect(described_class.graphql_name).to eq('FeatureFlag') }

  specify { expect(described_class).to require_graphql_authorizations(:read_feature_flag) }

  it 'requires read_feature_flag on the project from a granular token', :aggregate_failures do
    directive = described_class.directives.find { |d| d.is_a?(::Directives::Authz::GranularScope) }

    expect(directive.arguments[:permissions]).to eq(%w[read_feature_flag])
    expect(directive.arguments[:boundary_type]).to eq('project')
  end

  it 'has specific fields' do
    fields = %i[
      id
      name
      active
      path
      reference
    ]

    expect(described_class).to have_graphql_fields(*fields)
  end
end
