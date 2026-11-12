# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Authn::TokenExchange::Audience, feature_category: :system_access do
  let_it_be(:user) { create(:user) }

  describe '.find' do
    it 'finds an audience by name' do
      expect(described_class.find('gitlab-artifact-registry').name).to eq('gitlab-artifact-registry')
    end

    it 'returns nil for an unknown name' do
      expect(described_class.find('gitlab-unknown')).to be_nil
    end
  end

  describe '.names' do
    it 'lists every audience once', :aggregate_failures do
      expect(described_class.names).to include('gitlab-artifact-registry')
      expect(described_class.names).to eq(described_class.names.uniq)
    end
  end

  describe 'gitlab-artifact-registry' do
    subject(:audience) { described_class.find('gitlab-artifact-registry') }

    it 'lasts at most 12 hours' do
      expect(audience.max_ttl).to eq(12.hours.to_i)
    end

    it 'also grants the IAM data access audience' do
      expect(audience.audiences).to eq(%w[gitlab-artifact-registry gitlab-iam-data-access])
    end

    it 'is open to every user and to CI jobs', :aggregate_failures do
      expect(audience.enabled?(user)).to be(true)
      expect(audience.job_token_allowed?).to be(true)
    end
  end

  describe 'gitlab-autoflow' do
    subject(:audience) { described_class.find('gitlab-autoflow') }

    it 'grants no extra audience' do
      expect(audience.audiences).to eq(%w[gitlab-autoflow])
    end

    it 'is closed to CI jobs' do
      expect(audience.job_token_allowed?).to be(false)
    end

    it 'follows token_exchange_autoflow_audience', :aggregate_failures do
      stub_feature_flags(token_exchange_autoflow_audience: false)
      expect(audience.enabled?(user)).to be(false)

      stub_feature_flags(token_exchange_autoflow_audience: user)
      expect(audience.enabled?(user)).to be(true)
    end
  end
end
