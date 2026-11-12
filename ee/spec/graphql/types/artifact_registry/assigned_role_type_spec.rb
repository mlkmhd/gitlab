# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Types::ArtifactRegistry::AssignedRoleType, feature_category: :artifact_registry do
  specify { expect(described_class.graphql_name).to eq('ArtifactRegistryAssignedRole') }

  it 'exposes the expected fields' do
    expect(described_class).to have_graphql_fields(:key, :name)
  end
end
