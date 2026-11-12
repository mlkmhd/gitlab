# frozen_string_literal: true

require 'spec_helper'

RSpec.describe GitlabSchema.types['GroupReleaseStats'], feature_category: :release_orchestration do
  it { expect(described_class).to require_graphql_authorizations(:read_group_release_stats) }

  it 'requires read_release on the group from a granular token', :aggregate_failures do
    directive = described_class.directives.find { |d| d.is_a?(::Directives::Authz::GranularScope) }

    expect(directive.arguments[:permissions]).to eq(%w[read_release])
    expect(directive.arguments[:boundary_type]).to eq('group')
  end

  it 'has the expected fields' do
    expected_fields = %w[releasesCount releasesPercentage]

    expect(described_class).to include_graphql_fields(*expected_fields)
  end
end
