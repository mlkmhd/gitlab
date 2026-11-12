# frozen_string_literal: true

require 'spec_helper'

RSpec.describe SessionsHelper, feature_category: :system_access do
  include Devise::Test::ControllerHelpers

  describe '#unconfirmed_email?' do
    it 'returns true when the flash alert contains a devise failure unconfirmed message' do
      flash[:alert] = t(:unconfirmed, scope: [:devise, :failure])
      expect(helper.unconfirmed_email?).to be_truthy
    end

    it 'returns false when the flash alert does not contain a devise failure unconfirmed message' do
      flash[:alert] = 'something else'
      expect(helper.unconfirmed_email?).to be_falsey
    end
  end

  describe '#verification_data' do
    let(:user) { build_stubbed(:user) }

    context 'when user is not permitted to skip email otp' do
      it 'returns the expected data with skip_path being nil' do
        expect(helper.verification_data(user)).to match({
          username: user.username,
          obfuscated_email: obfuscated_email(user.email),
          verify_path: helper.session_path(:user),
          resend_path: users_resend_verification_code_path,
          skip_path: nil,
          show_resend_after: nil
        })
      end
    end

    context 'when user is permitted to skip email otp' do
      before do
        allow(helper).to receive(
          :permitted_to_skip_email_otp_in_warning_period?
        ).and_return(true)
      end

      it 'returns the expected data with skip_path being the correct route' do
        expect(helper.verification_data(user)).to match({
          username: user.username,
          obfuscated_email: obfuscated_email(user.email),
          verify_path: helper.session_path(:user),
          resend_path: users_resend_verification_code_path,
          skip_path: users_skip_verification_for_now_path,
          show_resend_after: nil
        })
      end
    end

    context 'when user has email_otp_last_sent_at set', :freeze_time do
      let(:sent_at) { 10.seconds.ago }
      let(:user) { build_stubbed(:user, user_detail: build_stubbed(:user_detail, email_otp_last_sent_at: sent_at)) }

      it 'includes the resend cooldown timestamp from show_email_otp_resend_after' do
        expect(helper.verification_data(user)[:show_resend_after]).to eq(helper.show_email_otp_resend_after(user))
      end
    end
  end

  describe '#obfuscated_email' do
    let(:email) { 'mail@example.com' }

    subject { helper.obfuscated_email(email) }

    it 'delegates to Gitlab::Utils::Email.obfuscated_email' do
      expect(Gitlab::Utils::Email).to receive(:obfuscated_email).with(email).and_call_original

      expect(subject).to eq('ma**@e******.com')
    end
  end

  describe '#session_expire_modal_data' do
    subject { helper.session_expire_modal_data }

    before do
      allow(Gitlab::Sessions::Expiry).to receive_messages(reported?: true, expires_at: 5)
    end

    it 'returns the expected data' do
      expect(subject).to match(a_hash_including({
        session_timeout: 5000,
        sign_in_url: a_string_including(/^http/)
      }))
    end

    it 'measures the deadline from the timestamp this request will commit' do
      allow(Gitlab::Sessions::CacheStore).to receive(:last_write_at_after_commit).and_return(42)

      subject

      expect(Gitlab::Sessions::Expiry).to have_received(:expires_at).with(anything, last_write_at: 42)
    end

    context 'when the session expiry cannot be derived' do
      before do
        allow(Gitlab::Sessions::Expiry).to receive(:expires_at).and_return(nil)
      end

      it { is_expected.to be_nil }
    end

    context 'when the instance reports no session expiry' do
      before do
        allow(Gitlab::Sessions::Expiry).to receive(:reported?).and_return(false)
        allow(Gitlab::Sessions::CacheStore).to receive(:last_write_at_after_commit)
      end

      it 'returns nil without predicting the deadline', :aggregate_failures do
        expect(subject).to be_nil
        expect(Gitlab::Sessions::CacheStore).not_to have_received(:last_write_at_after_commit)
      end
    end

    describe 'remember me deadline' do
      before do
        allow(Gitlab::Sessions::RememberMe).to receive(:expires_at).and_return(7)
      end

      it 'includes when the remember me cookie stops signing the user back in' do
        expect(subject).to include(remember_me_expires_at: 7000)
      end

      context 'without a valid remember me cookie' do
        before do
          allow(Gitlab::Sessions::RememberMe).to receive(:expires_at).and_return(nil)
        end

        it { is_expected.not_to have_key(:remember_me_expires_at) }
      end

      context 'when sessions expire from the time of sign-in' do
        before do
          stub_application_setting(session_expire_from_init: true)
        end

        it { is_expected.not_to have_key(:remember_me_expires_at) }
      end
    end
  end

  describe '#remember_me_enabled?' do
    subject { helper.remember_me_enabled? }

    context 'when application setting is enabled' do
      before do
        stub_application_setting(remember_me_enabled: true, session_expire_from_init: false)
      end

      it { is_expected.to be true }

      context 'and session_expire_from_init is enabled' do
        before do
          stub_application_setting(session_expire_from_init: true)
        end

        it { is_expected.to be false }
      end
    end

    context 'when application setting is disabled' do
      before do
        stub_application_setting(remember_me_enabled: false)
      end

      it { is_expected.to be false }
    end
  end

  describe '#fallback_to_email_otp_permitted?' do
    let_it_be_with_reload(:user) { create(:user) } # rubocop:disable RSpec/FactoryBot/AvoidCreate -- we need to create it

    it 'returns false' do
      expect(helper.fallback_to_email_otp_permitted?(user)).to be false
    end

    context 'when email_otp_enabled application setting is enabled' do
      before do
        stub_application_setting(email_otp_enabled: true)
      end

      context 'when user has email_otp_required_after set to nil' do
        before do
          user.update!(email_otp_required_after: nil)
        end

        it 'returns false' do
          expect(helper.fallback_to_email_otp_permitted?(user)).to be_falsy
        end
      end

      context 'when user has email_otp_required_after set to future date' do
        before do
          user.update!(email_otp_required_after: Time.zone.today + 1.day)
        end

        it 'returns false' do
          expect(helper.fallback_to_email_otp_permitted?(user)).to be false
        end
      end

      context 'when user is treated as locked by having an unlock token' do
        before do
          allow(user).to receive(:unlock_token).and_return('1234')
        end

        it 'returns false' do
          expect(helper.fallback_to_email_otp_permitted?(user)).to be_falsy
        end
      end

      context 'when user has email_otp_required_after set to today' do
        before do
          user.update!(email_otp_required_after: Time.zone.today)
        end

        it 'returns true' do
          expect(helper.fallback_to_email_otp_permitted?(user)).to be true
        end
      end

      context 'when user has email_otp_required_after set to past date' do
        before do
          user.update!(email_otp_required_after: Time.zone.today - 1.day)
        end

        it 'returns true' do
          expect(helper.fallback_to_email_otp_permitted?(user)).to be true
        end

        context 'when user is not allowed to use password authentication for web' do
          before do
            allow(user).to receive(:allow_password_authentication_for_web?).and_return(false)
          end

          it 'returns false' do
            expect(helper.fallback_to_email_otp_permitted?(user)).to be false
          end
        end

        context 'when the password was automatically set for user' do
          before do
            allow(user).to receive(:password_automatically_set?).and_return(true)
          end

          it 'returns false' do
            expect(helper.fallback_to_email_otp_permitted?(user)).to be false
          end
        end
      end
    end
  end

  describe '#passkey_authentication_data' do
    describe 'when remember_me is set' do
      it 'returns correct data' do
        expect(helper.passkey_authentication_data({
          remember_me: '1'
        })).to match(a_hash_including({
          path: users_passkeys_sign_in_path,
          remember_me: '1'
        }))
      end
    end

    describe 'when remember_me is not set' do
      it 'returns correct data' do
        expect(helper.passkey_authentication_data({})).to match(a_hash_including({
          path: users_passkeys_sign_in_path,
          remember_me: '0'
        }))
      end
    end
  end

  describe '#two_factor_authentication_app_data' do
    let(:user) { build_stubbed(:user) }
    let(:params) { { user: { remember_me: 1 } } }
    let(:remember_me_enabled) { true }

    before do
      allow(helper).to receive_messages(
        remember_me_enabled?: remember_me_enabled,
        fallback_to_email_otp_permitted?: false
      )
    end

    context 'when admin_mode is false' do
      it 'returns the user session path' do
        data = helper.two_factor_authentication_app_data(user: user, params: params)

        expect(data[:path]).to eq(user_session_path)
      end

      it 'returns remember_me_enabled as true when remember_me is enabled' do
        data = helper.two_factor_authentication_app_data(user: user, params: params)

        expect(data[:remember_me_enabled]).to eq('true')
      end

      it 'returns remember_me value from params' do
        data = helper.two_factor_authentication_app_data(user: user, params: params)

        expect(data[:remember_me]).to eq(1)
      end
    end

    describe 'active_method' do
      it 'reflects the submitted two_factor_method hint' do
        data = helper.two_factor_authentication_app_data(user: user, params: { two_factor_method: 'webauthn' })

        expect(data[:active_method]).to eq('webauthn')
      end

      it 'reflects a recovery two_factor_method hint' do
        data = helper.two_factor_authentication_app_data(user: user, params: { two_factor_method: 'recovery' })

        expect(data[:active_method]).to eq('recovery')
      end

      it 'is nil when nothing was submitted' do
        data = helper.two_factor_authentication_app_data(user: user, params: {})

        expect(data[:active_method]).to be_nil
      end
    end

    context 'when admin_mode is true' do
      it 'returns the admin session path' do
        data = helper.two_factor_authentication_app_data(user: user, params: params, admin_mode: true)

        expect(data[:path]).to eq(admin_session_path)
      end

      it 'flags admin_mode as true' do
        data = helper.two_factor_authentication_app_data(user: user, params: params, admin_mode: true)

        expect(data[:admin_mode]).to eq('true')
      end

      it 'returns remember_me_enabled as false' do
        data = helper.two_factor_authentication_app_data(user: user, params: params, admin_mode: true)

        expect(data[:remember_me_enabled]).to eq('false')
      end
    end

    context 'when remember_me is disabled' do
      let(:remember_me_enabled) { false }

      it 'returns remember_me_enabled as false' do
        data = helper.two_factor_authentication_app_data(user: user, params: params)

        expect(data[:remember_me_enabled]).to eq('false')
      end
    end

    context 'when user params is not present' do
      let(:params) { {} }

      it 'returns default remember_me value of 0' do
        data = helper.two_factor_authentication_app_data(user: user, params: params)

        expect(data[:remember_me]).to eq(0)
      end
    end

    it 'includes the enabled second-factor methods' do
      allow(user).to receive_messages(two_factor_otp_enabled?: true,
        can_use_existing_webauthn_authenticator_for_2fa?: false)

      data = helper.two_factor_authentication_app_data(user: user, params: params)

      expect(data[:totp_enabled]).to eq('true')
      expect(data[:webauthn_enabled]).to eq('false')
      expect(data[:email_enabled]).to eq('false')
      expect(data[:admin_mode]).to eq('false')
    end

    it 'treats a passkey usable for 2FA as webauthn_enabled, even without a second-factor device' do
      # webauthn_enabled mirrors can_use_existing_webauthn_authenticator_for_2fa? (passkey-inclusive),
      # matching the controller's challenge setup, not the narrower two_factor_webauthn_enabled?.
      allow(user).to receive_messages(two_factor_webauthn_enabled?: false,
        can_use_existing_webauthn_authenticator_for_2fa?: true)

      data = helper.two_factor_authentication_app_data(user: user, params: params)

      expect(data[:webauthn_enabled]).to eq('true')
    end

    context 'when fallback_to_email_otp is permitted' do
      before do
        allow(helper).to receive(:fallback_to_email_otp_permitted?).and_return(true)
        allow(helper).to receive(:verification_data).with(user).and_return({
          username: user.username,
          obfuscated_email: 'u***@example.com',
          verify_path: '/verify',
          resend_path: '/resend',
          skip_path: nil
        })
      end

      it 'sets email_enabled to true' do
        data = helper.two_factor_authentication_app_data(user: user, params: params)

        expect(data[:email_enabled]).to eq('true')
      end

      it 'includes send_email_otp_path' do
        data = helper.two_factor_authentication_app_data(user: user, params: params)

        expect(data[:send_email_otp_path]).to eq(users_fallback_to_email_otp_path)
      end

      it 'includes email_verification_data as JSON with only the fields the Vue screen reads' do
        data = helper.two_factor_authentication_app_data(user: user, params: params)

        expect(data[:email_verification_data]).to be_present
        parsed_data = Gitlab::Json.parse(data[:email_verification_data])
        expect(parsed_data.keys)
          .to contain_exactly('obfuscated_email', 'verify_path', 'resend_path', 'username')
        expect(parsed_data['obfuscated_email']).to eq('u***@example.com')
      end

      context 'and admin_mode is true' do
        it 'disables email OTP (unsupported for admin re-authentication)' do
          data = helper.two_factor_authentication_app_data(user: user, params: params, admin_mode: true)

          expect(data[:email_enabled]).to eq('false')
          expect(data.key?(:email_verification_data)).to be false
        end
      end
    end

    context 'when fallback_to_email_otp is not permitted' do
      it 'does not include email_verification_data' do
        data = helper.two_factor_authentication_app_data(user: user, params: params)

        expect(data.key?(:email_verification_data)).to be false
      end
    end
  end

  describe '#show_passkey_immediately?' do
    it 'returns true' do
      expect(helper.show_passkey_immediately?).to be(true)
    end
  end

  describe '#sign_in_form_app_data' do
    subject(:json) { Gitlab::Json.parse(helper.sign_in_form_app_data) }

    it 'returns expected json' do
      allow(helper).to receive_messages(
        unconfirmed_email?: false,
        captcha_enabled?: false,
        captcha_on_login_required?: false
      )

      expect(json).to match(
        {
          'sign_in_path' => '/users/sign_in',
          'users_sign_in_path_path' => '/users/sign_in_path',
          'passkeys_sign_in_path' => '/users/passkeys/sign_in',
          'is_unconfirmed_email' => false,
          'new_user_confirmation_path' => '/users/confirmation/new',
          'new_password_path' => '/users/password/new',
          'show_captcha' => false,
          'is_remember_me_enabled' => true,
          'show_passkey_immediately' => true
        }
      )
    end

    context 'when captcha_enabled? is true' do
      it 'returns expected json' do
        allow(helper).to receive_messages(
          unconfirmed_email?: false,
          captcha_enabled?: true,
          captcha_on_login_required?: false
        )

        expect(json['show_captcha']).to be(true)
      end
    end

    context 'when captcha_on_login_required? is true' do
      it 'returns expected json' do
        allow(helper).to receive_messages(
          unconfirmed_email?: false,
          captcha_enabled?: false,
          captcha_on_login_required?: true
        )

        expect(json['show_captcha']).to be(true)
      end
    end
  end
end
