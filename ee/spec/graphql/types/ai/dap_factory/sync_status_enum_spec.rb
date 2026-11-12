# frozen_string_literal: true

require 'spec_helper'

RSpec.describe GitlabSchema.types['DapFactorySyncStatus'], feature_category: :dap_triggers do
  it 'exposes every SyncResult status' do
    expect(described_class.values.values.map(&:value)).to match_array(::Ai::DapFactory::SyncResult::STATUSES)
  end
end
