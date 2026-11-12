# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Security::SecretDetection::ValidityChecks::GitlabTokenVerifier, feature_category: :secret_detection do
  let(:pat_type) { 'gitlab_personal_access_token' }
  let_it_be(:active) { create(:personal_access_token).token }
  let_it_be(:revoked) { create(:personal_access_token, :revoked).token }

  subject(:verifier) { described_class.new(organization_id: nil) }

  describe '#verify' do
    it 'returns a status per raw token' do
      expect(verifier.verify(pat_type, [active, revoked, 'absent'])).to eq(
        active => { status: 'active' },
        revoked => { status: 'inactive' },
        'absent' => { status: 'unknown' }
      )
    end

    it 'looks up all tokens of a type in one call' do
      expect_next_instance_of(Security::SecretDetection::TokenLookupService) do |lookup|
        expect(lookup).to receive(:find).once.with(pat_type, [active, revoked]).and_call_original
      end

      verifier.verify(pat_type, [active, revoked])
    end

    it 'answers unsupported token types without a lookup' do
      allow_next_instance_of(Security::SecretDetection::TokenLookupService) do |lookup|
        expect(lookup).not_to receive(:find)
      end

      expect(verifier.verify('anthropic_key', %w[sk-ant-1 sk-ant-2])).to eq(
        'sk-ant-1' => { error: 'unsupported_token_type' },
        'sk-ant-2' => { error: 'unsupported_token_type' }
      )
    end
  end
end
