# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'Session expiry modal deadline', :clean_gitlab_redis_sessions, feature_category: :system_access do
  include ApiHelpers
  include LoginHelpers

  let_it_be(:user) { create(:user) }

  def header_deadline_ms
    response.headers[Gitlab::Middleware::SessionExpiryHeader::HEADER].to_i * 1000
  end

  def page_deadline_ms
    Nokogiri::HTML(response.body).at_css('#js-session-expire-modal')['data-session-timeout'].to_i
  end

  before do
    stub_basic_saml_config
    login_as(user)
    get root_path
  end

  it 'matches the header when the request writes the session', :aggregate_failures do
    travel_to(2.hours.from_now) do
      get root_path

      expect(header_deadline_ms).to be_positive
      expect(page_deadline_ms).to eq(header_deadline_ms)
    end
  end

  it 'is never later than the header inside the write throttle window', :aggregate_failures do
    travel_to(1.minute.from_now) do
      get root_path

      expect(header_deadline_ms).to be_positive
      expect(page_deadline_ms).to be <= header_deadline_ms
    end
  end

  context 'when no deadline is reported' do
    it 'renders no modal when the flag is disabled' do
      stub_feature_flags(session_expire_modal_on_saml_instances: false)

      get root_path

      expect(response.body).not_to include('js-session-expire-modal')
    end

    it 'renders no modal when SAML is not configured' do
      allow(Gitlab::Auth::Saml::Config).to receive(:enabled?).and_return(false)

      get root_path

      expect(response.body).not_to include('js-session-expire-modal')
    end
  end

  # The modal keeps a remembered user's session alive with this request, so it has to save
  # the session and report the new deadline.
  it 'is pushed back by the keep-alive request', :aggregate_failures do
    deadline_after_page_load = header_deadline_ms

    travel_to(2.hours.from_now) do
      get api('/version')

      expect(response).to have_gitlab_http_status(:ok)
      expect(header_deadline_ms).to eq(deadline_after_page_load + 2.hours.in_milliseconds)
    end
  end
end
