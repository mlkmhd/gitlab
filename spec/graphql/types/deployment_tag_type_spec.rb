# frozen_string_literal: true

require 'spec_helper'

RSpec.describe GitlabSchema.types['DeploymentTag'], feature_category: :continuous_delivery do
  specify { expect(described_class.graphql_name).to eq('DeploymentTag') }

  it 'has the expected fields' do
    expected_fields = %w[
      name path web_path
    ]

    expect(described_class).to have_graphql_fields(*expected_fields)
  end

  it 'skips granular token authorization because the parent authorizes' do
    directive = described_class.directives.find { |d| d.is_a?(::Directives::Authz::GranularScope) }

    expect(directive.arguments[:skip_reason]).to eq('parent_authorizes')
    expect(directive.arguments[:parent_authorizes]).to eq(%w[read_deployment])
  end
end
