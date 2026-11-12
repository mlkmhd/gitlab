# frozen_string_literal: true

require 'spec_helper'
require_migration!

RSpec.describe BackfillMobileDevicePushSubscriptionTokenDigests, migration: :gitlab_main_user,
  feature_category: :notifications do
  let(:organizations) { table(:organizations) }
  let(:users) { table(:users) }
  let(:subscriptions) { table(:mobile_device_push_subscriptions) }

  let(:organization) { organizations.create!(path: 'org') }
  let(:user) do
    users.create!(email: 'user@example.com', username: 'user', projects_limit: 10, organization_id: organization.id)
  end

  let(:token) { SecureRandom.hex(32) }
  let(:other_token) { SecureRandom.hex(32) }

  # The ciphertext the application model produced before this migration.
  def deterministic_ciphertext(plaintext)
    type = ActiveRecord::Encryption::EncryptedAttributeType.new(
      scheme: ActiveRecord::Encryption::Scheme.new(deterministic: true),
      cast_type: ActiveRecord::Type::Json.new
    )

    Gitlab::Json::SafeParser.parse(type.serialize(plaintext))
  end

  def create_legacy_subscription(plaintext, **attributes)
    subscriptions.create!(
      { user_id: user.id, device_token: deterministic_ciphertext(plaintext), apns_environment: 0 }.merge(attributes)
    )
  end

  # A row already written by the 19.6 application code.
  def create_migrated_subscription(plaintext, **attributes)
    described_class::MobileDevicePushSubscription.create!(
      {
        user_id: user.id,
        device_token: plaintext,
        device_token_digest: Digest::SHA256.hexdigest(plaintext),
        apns_environment: 0
      }.merge(attributes)
    )
  end

  def decrypted_token(subscription)
    described_class::MobileDevicePushSubscription.find(subscription.id).device_token
  end

  describe '#up' do
    it 'sets the digest and re-encrypts the token without the deterministic scheme' do
      subscription = create_legacy_subscription(token)
      other = create_legacy_subscription(other_token, apns_environment: 1)

      migrate!

      expect(subscription.reload.device_token_digest).to eq(Digest::SHA256.hexdigest(token))
      expect(subscription.device_token).not_to eq(deterministic_ciphertext(token))
      expect(decrypted_token(subscription)).to eq(token)
      expect(other.reload.device_token_digest).to eq(Digest::SHA256.hexdigest(other_token))
      expect(decrypted_token(other)).to eq(other_token)
    end

    it 'skips a row whose token does not decrypt and leaves its digest NULL' do
      foreign_ciphertext = {
        'p' => Base64.strict_encode64(SecureRandom.random_bytes(32)),
        'h' => {
          'iv' => Base64.strict_encode64(SecureRandom.random_bytes(12)),
          'at' => Base64.strict_encode64(SecureRandom.random_bytes(16))
        }
      }
      undecryptable = subscriptions.create!(user_id: user.id, device_token: foreign_ciphertext, apns_environment: 0)
      legacy = create_legacy_subscription(token)

      migrate!

      expect(subscriptions.find(undecryptable.id).device_token_digest).to be_nil
      expect(subscriptions.find(undecryptable.id).device_token).to eq(foreign_ciphertext)
      expect(subscriptions.find(legacy.id).device_token_digest).to eq(Digest::SHA256.hexdigest(token))
    end

    it 'skips a row whose token does not decrypt to a string, as under the database testing stub' do
      allow(ActiveRecord::Encryption.encryptor).to receive(:decrypt).and_return('placeholder cryptogram for testing')
      legacy = create_legacy_subscription(token)
      ciphertext = subscriptions.find(legacy.id).device_token

      migrate!

      expect(subscriptions.find(legacy.id).device_token_digest).to be_nil
      expect(subscriptions.find(legacy.id).device_token).to eq(ciphertext)
    end

    it 'leaves rows that already carry a digest untouched' do
      subscription = create_migrated_subscription(token)
      ciphertext = subscriptions.find(subscription.id).device_token

      migrate!

      expect(subscriptions.find(subscription.id).device_token).to eq(ciphertext)
    end

    it 'drops a legacy duplicate of a more recently seen migrated row' do
      migrated = create_migrated_subscription(token, last_seen_at: 1.hour.ago)
      legacy = create_legacy_subscription(token, last_seen_at: 2.hours.ago)

      migrate!

      expect(subscriptions.where(id: legacy.id)).not_to exist
      expect(subscriptions.find(migrated.id).device_token_digest).to eq(Digest::SHA256.hexdigest(token))
    end

    it 'replaces a migrated row with its more recently seen legacy duplicate' do
      migrated = create_migrated_subscription(token, last_seen_at: 2.hours.ago)
      legacy = create_legacy_subscription(token, last_seen_at: 1.hour.ago)

      migrate!

      expect(subscriptions.where(id: migrated.id)).not_to exist
      expect(subscriptions.find(legacy.id).device_token_digest).to eq(Digest::SHA256.hexdigest(token))
      expect(decrypted_token(legacy)).to eq(token)
    end

    context 'when a registration runs between the duplicate lookup and the write' do
      let(:digest) { Digest::SHA256.hexdigest(token) }

      def after_duplicate_lookup(&block)
        allow(described_class::MobileDevicePushSubscription).to receive(:duplicate_of)
          .and_wrap_original { |original, *args| original.call(*args).tap(&block) }
      end

      it 'keeps a migrated row that the registration refreshed after the lookup' do
        migrated = create_migrated_subscription(token, last_seen_at: 2.hours.ago)
        legacy = create_legacy_subscription(token, last_seen_at: 1.hour.ago)
        after_duplicate_lookup { subscriptions.where(id: migrated.id).update_all(last_seen_at: Time.current) }

        migrate!

        expect(subscriptions.where(id: legacy.id)).not_to exist
        expect(subscriptions.find(migrated.id).device_token_digest).to eq(digest)
      end

      it 'yields to a row that the registration inserted after the lookup' do
        legacy = create_legacy_subscription(token, last_seen_at: 1.hour.ago)
        inserted = nil
        after_duplicate_lookup { inserted = create_migrated_subscription(token) }

        migrate!

        expect(subscriptions.where(id: legacy.id)).not_to exist
        expect(subscriptions.find(inserted.id).device_token_digest).to eq(digest)
      end
    end
  end
end
