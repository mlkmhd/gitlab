# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Types::PermissionTypes::Deployment, feature_category: :continuous_delivery do
  it 'exposes the update_deployment and destroy_deployment permissions' do
    expected_permissions = %i[update_deployment destroy_deployment]

    expect(described_class).to include_graphql_fields(*expected_permissions)
  end

  it 'skips granular token authorization because the parent authorizes' do
    directive = described_class.directives.find { |d| d.is_a?(::Directives::Authz::GranularScope) }

    expect(directive.arguments[:skip_reason]).to eq('parent_authorizes')
    expect(directive.arguments[:parent_authorizes]).to eq(%w[read_deployment])
  end
end
