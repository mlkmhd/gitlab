# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Ai::DuoWorkflows::WorkloadCredential, feature_category: :duo_agent_platform do
  describe 'EXPIRES_IN' do
    it 'matches the ceiling the application setting validator allows' do
      expect(described_class::EXPIRES_IN).to eq(::ApplicationSetting::DEFAULT_OAUTH_ACCESS_TOKEN_EXPIRES_IN.seconds)
    end

    it 'is a lifetime an admin can configure for OAuth access tokens' do
      setting = build(:application_setting, oauth_access_token_expires_in: described_class::EXPIRES_IN.to_i)

      expect(setting).to be_valid
    end
  end
end
