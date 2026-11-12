# frozen_string_literal: true

require 'spec_helper'

RSpec.describe GitlabSchema.types['TriageAndRemediationTriggerFlowStatus'],
  feature_category: :security_asset_inventories do
  it { expect(described_class).to have_graphql_fields(:trigger_type, :flow_status, :flow_name).only }

  it 'uses the shared flow status enum', :aggregate_failures do
    expect(described_class.fields['flowStatus'].type.of_type).to eq(Types::Security::TriageAndRemediationFlowStatusEnum)
    expect(described_class.fields['triggerType'].type.of_type).to eq(Types::Security::ScanProfileTriggerTypeEnum)
  end
end
