# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Mutations::Ci::NamespaceCiCdSettingsUpdate, feature_category: :runner_core do
  it { expect(described_class).to require_graphql_authorizations(:update_runners_setting) }
end
