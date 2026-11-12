# frozen_string_literal: true

require 'spec_helper'

RSpec.describe GitlabSchema.types['DeploymentApproval'], feature_category: :continuous_delivery do
  specify { expect(described_class.graphql_name).to eq('DeploymentApproval') }

  it 'includes the expected fields' do
    expected_fields = %w[
      user status created_at updated_at comment
    ]

    expect(described_class).to include_graphql_fields(*expected_fields)
  end

  it 'requires read_deployment on the project from a granular token', :aggregate_failures do
    directive = described_class.directives.find { |d| d.is_a?(::Directives::Authz::GranularScope) }

    expect(directive.arguments[:permissions]).to eq(%w[read_deployment])
    expect(directive.arguments[:boundary]).to eq('deployment_project')
    expect(directive.arguments[:boundary_type]).to eq('project')
  end
end
