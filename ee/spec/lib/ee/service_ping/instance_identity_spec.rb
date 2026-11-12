# frozen_string_literal: true

require 'spec_helper'

RSpec.describe ServicePing::InstanceIdentity, feature_category: :service_ping do
  describe '.to_h unique_instance_id' do
    subject(:unique_instance_id) { described_class.to_h[:unique_instance_id] }

    let(:cloud_connector_instance_uid) { 'a3c1b8e2-8ea1-4a3f-9c1a-2d7b6f2c9e11' }

    before do
      allow(::CloudConnector::Tokens).to receive(:cloud_connector_instance_uid)
        .and_return(cloud_connector_instance_uid)
    end

    it 'is the Cloud Connector instance uid that CustomersDot issued' do
      expect(unique_instance_id).to eq(cloud_connector_instance_uid)
    end

    context 'when the Cloud Connector token has no instance uid' do
      let(:cloud_connector_instance_uid) { nil }

      it 'falls back to the instance-derived uuid' do
        expect(unique_instance_id).to eq(Gitlab::GlobalAnonymousId.instance_uuid)
      end
    end

    context 'on GitLab.com', :saas do
      it 'keeps the instance-derived uuid without reading the token' do
        expect(unique_instance_id).to eq(Gitlab::GlobalAnonymousId.instance_uuid)
        expect(::CloudConnector::Tokens).not_to have_received(:cloud_connector_instance_uid)
      end
    end
  end
end
