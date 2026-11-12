# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Doorkeeper::AccessToken, feature_category: :system_access do
  describe 'associations' do
    it { is_expected.to belong_to(:organization).class_name('Organizations::Organization').optional(false) }
  end

  shared_examples 'an access token stuck to the database load balancer' do
    it_behaves_like 'a Doorkeeper model stuck to the database load balancer' do
      let(:namespace) { :oauth_token }
      let(:record) { create(:oauth_access_token, use_refresh_token: true) }
      let(:lookups) { { by_token: record.plaintext_token, by_refresh_token: record.plaintext_refresh_token } }
      let(:expected_stuck_secrets) { [record.plaintext_token, record.plaintext_refresh_token] }
    end
  end

  it_behaves_like 'an access token stuck to the database load balancer'

  context 'when the routable_oauth_access_token feature flag is disabled' do
    before do
      stub_feature_flags(routable_oauth_access_token: false)
    end

    it_behaves_like 'an access token stuck to the database load balancer'
  end
end
