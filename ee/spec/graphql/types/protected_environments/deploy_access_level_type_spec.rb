# frozen_string_literal: true

require 'spec_helper'

RSpec.describe GitlabSchema.types['ProtectedEnvironmentDeployAccessLevel'], feature_category: :continuous_delivery do
  specify { expect(described_class.graphql_name).to eq('ProtectedEnvironmentDeployAccessLevel') }

  it 'includes the expected fields' do
    expected_fields = %w[
      accessLevel group user
    ]

    expect(described_class).to include_graphql_fields(*expected_fields)
  end

  it 'requires read_protected_environment on the project or group of the protected environment' do
    directives = described_class.directives.select { |d| d.is_a?(::Directives::Authz::GranularScope) }

    expect(directives.map { |d| d.arguments.to_h.slice(:permissions, :boundary, :boundary_type) }).to contain_exactly(
      { permissions: %w[read_protected_environment], boundary: 'protected_environment_project',
        boundary_type: 'project' },
      { permissions: %w[read_protected_environment], boundary: 'protected_environment_group', boundary_type: 'group' }
    )
  end
end
