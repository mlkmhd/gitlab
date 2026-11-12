# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Security::TokenStatus, feature_category: :secret_detection do
  describe '.for' do
    it 'returns unknown when no token was found' do
      expect(described_class.for(nil)).to eq('unknown')
    end

    it 'returns active for an active token' do
      expect(described_class.for(build_stubbed(:personal_access_token))).to eq('active')
    end

    it 'returns inactive for a revoked token' do
      expect(described_class.for(build_stubbed(:personal_access_token, :revoked))).to eq('inactive')
    end

    it 'returns active for a token without active?' do
      expect(described_class.for(Object.new)).to eq('active')
    end

    it 'returns a key of STATUSES' do
      tokens = [nil, Object.new, build_stubbed(:personal_access_token), build_stubbed(:personal_access_token, :revoked)]

      expect(tokens.map { |token| described_class.for(token) })
        .to all(be_in(described_class::STATUSES.keys.map(&:to_s)))
    end
  end
end
