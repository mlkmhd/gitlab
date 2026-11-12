# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'layouts/_session_expire_modal', feature_category: :system_access do
  let(:user) { build_stubbed(:user) }
  let(:session_expire_modal_data) { { session_timeout: 5000 } }

  before do
    allow(view).to receive_messages(current_user: user, session_expire_modal_data: session_expire_modal_data)
  end

  it 'renders the modal' do
    render

    expect(rendered).to have_selector('#js-session-expire-modal')
  end

  context 'when the session expiry cannot be derived' do
    let(:session_expire_modal_data) { nil }

    it 'does not render the modal' do
      render

      expect(rendered).not_to have_selector('#js-session-expire-modal')
    end
  end

  context 'when there is no signed in user' do
    let(:user) { nil }

    it 'does not render the modal' do
      render

      expect(rendered).not_to have_selector('#js-session-expire-modal')
    end
  end
end
