# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Notifications::MobileDevicePushSubscriptions::UnregisterService, feature_category: :notifications do
  let_it_be(:user) { create(:user) }
  let_it_be(:other_user) { create(:user) }

  let(:device_token) { SecureRandom.hex(32) }

  def unregister(user:, device_token:)
    described_class.new(user: user, device_token: device_token).execute
  end

  describe '#execute' do
    it 'deletes the user subscriptions for the token across environments' do
      create(:mobile_device_push_subscription, user: user, device_token: device_token)
      create(:mobile_device_push_subscription, :sandbox, user: user, device_token: device_token)
      other = create(:mobile_device_push_subscription, user: user)

      expect(Gitlab::AppLogger).not_to receive(:info)
        .with(hash_including(Labkit::Fields::CLASS_NAME => described_class.name))

      response = unregister(user: user, device_token: device_token)

      expect(response).to be_success
      expect(user.mobile_device_push_subscriptions).to contain_exactly(other)
    end

    it 'deletes subscriptions another user registered for the token across environments' do
      create(:mobile_device_push_subscription, user: other_user, device_token: device_token)
      create(:mobile_device_push_subscription, :sandbox, user: other_user, device_token: device_token)

      expect(Gitlab::AppLogger).to receive(:info).with(
        hash_including(
          Labkit::Fields::CLASS_NAME => described_class.name,
          Labkit::Fields::GL_USER_ID => user.id,
          'other_user_ids' => [other_user.id],
          'other_users_subscriptions_count' => 2
        )
      )

      response = unregister(user: user, device_token: device_token)

      expect(response).to be_success
      expect(Notifications::MobileDevicePushSubscription.with_device_token(device_token)).to be_empty
    end

    it 'keeps the other user subscriptions for other tokens' do
      create(:mobile_device_push_subscription, user: other_user, device_token: device_token)
      other = create(:mobile_device_push_subscription, user: other_user)

      response = unregister(user: user, device_token: device_token)

      expect(response).to be_success
      expect(other_user.mobile_device_push_subscriptions).to contain_exactly(other)
    end

    it 'returns a not_found error for an unknown token' do
      response = unregister(user: user, device_token: device_token)

      expect(response).to be_error
      expect(response.reason).to eq(:not_found)
    end
  end
end
