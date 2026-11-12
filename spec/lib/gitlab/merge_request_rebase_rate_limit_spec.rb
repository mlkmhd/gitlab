# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Gitlab::MergeRequestRebaseRateLimit, feature_category: :code_review_workflow do
  let(:user) { build_stubbed(:user) }

  describe '.throttled?' do
    it 'returns the rate limiter decision for the user' do
      expect(Gitlab::ApplicationRateLimiter).to receive(:throttled?)
        .with(:merge_requests_rebase, scope: { user: user }).and_return(true)

      expect(described_class.throttled?(user)).to be(true)
    end

    context 'when merge_requests_rebase_rate_limit is disabled' do
      before do
        stub_feature_flags(merge_requests_rebase_rate_limit: false)
      end

      it 'returns false without checking the rate limiter' do
        expect(Gitlab::ApplicationRateLimiter).not_to receive(:throttled?)

        expect(described_class.throttled?(user)).to be(false)
      end
    end
  end

  describe '#check_merge_request_rebase_rate_limit!' do
    let(:host) do
      Class.new do
        include Gitlab::MergeRequestRebaseRateLimit

        attr_reader :current_user

        def initialize(current_user)
          @current_user = current_user
        end

        def check_rate_limit!(key, scope:); end
      end.new(user)
    end

    it 'checks the rate limit for the current user' do
      expect(host).to receive(:check_rate_limit!).with(:merge_requests_rebase, scope: { user: user })

      host.check_merge_request_rebase_rate_limit!
    end

    context 'when merge_requests_rebase_rate_limit is disabled' do
      before do
        stub_feature_flags(merge_requests_rebase_rate_limit: false)
      end

      it 'does not check the rate limit' do
        expect(host).not_to receive(:check_rate_limit!)

        host.check_merge_request_rebase_rate_limit!
      end
    end
  end
end
