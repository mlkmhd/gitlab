# frozen_string_literal: true

# Requires `request` (opens the page), `user` (can apply security scan profiles),
# `developer` (can open the page but cannot apply) and `callout_feature_name`.
RSpec.shared_examples 'dismisses the security nav indicator on view' do
  let(:callout) { Users::Callout.find_by(user: user, feature_name: callout_feature_name) }

  before do
    sign_in(user)
  end

  context 'on a date before the indicator expires' do
    around do |example|
      travel_to(::Security::NavIndicator::EXPIRES_ON - 1.day) { example.run }
    end

    it 'dismisses the page callout for the user' do
      request

      expect(callout).to be_present
    end

    context 'when the feature flag is disabled' do
      before do
        stub_feature_flags(security_nav_indicator: false)
      end

      it 'does not dismiss the callout' do
        request

        expect(callout).to be_nil
      end
    end

    context 'when the callout is already dismissed' do
      before do
        create(:callout, user: user, feature_name: callout_feature_name)
      end

      it 'does not dismiss it again' do
        expect(Users::DismissCalloutService).not_to receive(:new)

        request
      end
    end

    context 'when the user cannot apply security scan profiles' do
      before do
        sign_in(developer)
      end

      it 'does not dismiss the callout' do
        request

        expect(response).to have_gitlab_http_status(:ok)
        expect(Users::Callout.find_by(user: developer, feature_name: callout_feature_name)).to be_nil
      end
    end
  end

  context 'when the indicator has expired' do
    around do |example|
      travel_to(::Security::NavIndicator::EXPIRES_ON + 1.day) { example.run }
    end

    it 'does not dismiss the callout' do
      request

      expect(callout).to be_nil
    end
  end
end
