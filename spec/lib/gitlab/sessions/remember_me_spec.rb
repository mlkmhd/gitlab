# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Gitlab::Sessions::RememberMe, :freeze_time, feature_category: :system_access do
  describe '.expires_at' do
    subject(:expires_at) { described_class.expires_at(user, cookies) }

    let(:user) { create(:user) }
    let(:cookies) { ActionDispatch::TestRequest.create.cookie_jar }

    context 'without a remember me cookie' do
      it { is_expected.to be_nil }
    end

    context 'with a remember me cookie' do
      let(:issued_at) { Time.current }

      before do
        # Devise accepts only a cookie issued after remember_created_at.
        user.update!(remember_created_at: 1.minute.ago)
        user.remember_me!
        cookies.signed['remember_user_token'] = User.serialize_into_cookie(user)
      end

      it 'returns when the cookie stops signing the user back in' do
        expect(expires_at).to eq(issued_at.to_i + User.remember_for.to_i)
      end

      context 'when the cookie is older than the remember me period' do
        it 'returns nil' do
          travel(User.remember_for + 1.minute)

          expect(expires_at).to be_nil
        end
      end

      context 'when the remember me tokens were revoked' do
        before do
          user.invalidate_all_remember_tokens!
        end

        it { is_expected.to be_nil }
      end

      context 'when remember me is disabled by the admin' do
        before do
          stub_application_setting(allow_user_remember_me: false)
        end

        it { is_expected.to be_nil }
      end

      context 'when the cookie belongs to another user' do
        subject(:expires_at) { described_class.expires_at(other_user, cookies) }

        let(:other_user) { create(:user, remember_created_at: 1.minute.ago) }

        before do
          other_user.remember_me!
        end

        it { is_expected.to be_nil }
      end
    end

    context 'with a cookie that is not signed' do
      before do
        cookies['remember_user_token'] = 'tampered'
      end

      it { is_expected.to be_nil }
    end

    context 'with a signed cookie in an unexpected format' do
      before do
        cookies.signed['remember_user_token'] = 'not-a-devise-cookie'
      end

      it { is_expected.to be_nil }
    end
  end
end
