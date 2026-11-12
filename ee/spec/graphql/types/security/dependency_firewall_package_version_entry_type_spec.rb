# frozen_string_literal: true

require 'spec_helper'

RSpec.describe GitlabSchema.types['DependencyFirewallPackageVersionEntry'], feature_category: :dependency_firewall do
  it 'has the expected fields' do
    expect(described_class).to have_graphql_fields(:name, :version, :reason, :reference_link)
  end
end
