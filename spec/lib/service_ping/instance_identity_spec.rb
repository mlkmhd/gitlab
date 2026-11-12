# frozen_string_literal: true

require 'spec_helper'

RSpec.describe ServicePing::InstanceIdentity, feature_category: :service_ping do
  describe '.to_h' do
    subject(:identity) { described_class.to_h }

    it 'resolves each field from live instance state' do
      expect(identity).to eq(
        instance_id: Gitlab::GlobalAnonymousId.instance_id,
        unique_instance_id: Gitlab::GlobalAnonymousId.instance_uuid,
        host_name: Gitlab.config.gitlab.host,
        instance_version: Gitlab.version_info.to_s
      )
    end
  end
end
