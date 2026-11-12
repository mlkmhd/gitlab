# frozen_string_literal: true

require 'spec_helper'

RSpec.describe WorkItems::BulkUpdateRateLimiter, :clean_gitlab_redis_rate_limiting, :freeze_time,
  feature_category: :team_planning do
  let_it_be(:user) { create(:user) }

  let(:item_count) { 3 }

  subject(:check) { described_class.new(user: user, item_count: item_count).check! }

  before do
    stub_application_setting(work_item_update_limit: 5)
  end

  it 'charges one unit per item to the work item update limit' do
    check

    # Three items use three of the five updates, so two more calls pass and the third is throttled.
    throttled = Array.new(3) { ::Gitlab::ApplicationRateLimiter.throttled?(:work_item_update, scope: { user: user }) }

    expect(throttled).to eq([false, false, true])
  end

  context 'when the batch is larger than the limit' do
    let(:item_count) { 7 }

    it 'rejects the batch without charging either counter' do
      expect(::Gitlab::ApplicationRateLimiter).not_to receive(:throttled?)

      expect { check }.to raise_error(
        described_class::TooManyItemsError, 'No more than 5 items can be updated at the same time'
      )
    end

    context 'when the limit is one item' do
      let(:item_count) { 2 }

      before do
        stub_application_setting(work_item_update_limit: 1)
      end

      it 'uses the singular message' do
        expect { check }.to raise_error(
          described_class::TooManyItemsError, 'No more than 1 item can be updated at the same time'
        )
      end
    end

    context 'when the work item update limit is not enforced yet' do
      before do
        stub_feature_flags(work_item_update_rate_limit: false)
      end

      it 'lets the batch through and counts it in log mode', :request_store do
        expect { check }.not_to raise_error

        expect(::Gitlab::Instrumentation::RateLimitState.payload).to eq(
          rate_limit_state: %w[applimiter_work_item_update:limit_work_item_updates_by_user_log:log]
        )
      end
    end

    context 'when the user is in the throttle allowlist' do
      before do
        allow(::Gitlab::RackAttack).to receive(:user_allowlist).and_return(Set.new([user.id]))
        ::Gitlab::ApplicationRateLimiter.clear_memoization(:gitlab_throttle_user_allowlist)
      end

      after do
        ::Gitlab::ApplicationRateLimiter.clear_memoization(:gitlab_throttle_user_allowlist)
      end

      it 'lets the batch through' do
        expect { check }.not_to raise_error
      end
    end
  end

  context 'when the user is at the work item update limit' do
    before do
      5.times { ::Gitlab::ApplicationRateLimiter.throttled?(:work_item_update, scope: { user: user }) }
    end

    it 'raises a rate limited error' do
      expect { check }.to raise_error(
        ::RateLimitedService::RateLimitedError,
        'This endpoint has been requested too many times. Try again later.'
      )
    end
  end

  context 'when the user is at the bulk update limit' do
    before do
      allow(::Gitlab::ApplicationRateLimiter).to receive(:throttled?).and_call_original
      allow(::Gitlab::ApplicationRateLimiter).to receive(:throttled?)
        .with(:work_item_bulk_update, scope: { user: user }).and_return(true)
    end

    it 'raises a rate limited error without charging the work item update limit' do
      expect(::Gitlab::ApplicationRateLimiter).not_to receive(:throttled?)
        .with(:work_item_update, hash_including(scope: { user: user }))

      expect { check }.to raise_error(::RateLimitedService::RateLimitedError)
    end

    context 'when the work_item_bulk_update_rate_limit feature flag is disabled' do
      before do
        stub_feature_flags(work_item_bulk_update_rate_limit: false)
      end

      it 'skips the bulk update limit' do
        expect { check }.not_to raise_error
      end
    end
  end
end
