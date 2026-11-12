# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Types::Ai::DapFactory::ValidationMessageType, feature_category: :dap_triggers do
  specify { expect(described_class.graphql_name).to eq('DapFactoryValidationMessage') }

  it 'has the expected fields' do
    expect(described_class).to have_graphql_fields(:path, :code, :message)
  end
end
