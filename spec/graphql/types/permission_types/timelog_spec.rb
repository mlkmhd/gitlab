# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Types::PermissionTypes::Timelog, feature_category: :team_planning do
  it 'exposes the timelog permissions' do
    expect(described_class).to have_graphql_fields(:admin_timelog, :delete_timelog)
  end
end
