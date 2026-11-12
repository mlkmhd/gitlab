# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'User views session expiry modal', :js, feature_category: :system_access do
  let_it_be(:user) { create(:user) }

  let(:modal_title) { s_('SessionExpire|Your session has expired') }

  before do
    allow(Gitlab::Auth::Saml::Config).to receive(:enabled?).and_return(true)

    # Stubbed because neither travelling in time nor a short session duration moves the
    # browser clock the modal compares against.
    allow(Gitlab::Sessions::Expiry).to receive(:expires_at).and_return(1.minute.ago.to_i)

    sign_in(user)
  end

  it 'warns that the session expired' do
    visit root_path

    expect(page).to have_content(modal_title)
  end
end
