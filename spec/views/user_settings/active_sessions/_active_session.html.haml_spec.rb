# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'user_settings/active_sessions/_active_session.html.haml', :aggregate_failures,
  feature_category: :user_profile do
  let(:time) { Time.zone.parse('2018-03-12 09:06') }
  let(:browser) { 'Firefox' }
  let(:date) { I18n.l(time, format: :short) }
  let(:translations) { {} }
  let(:active_session) do
    ActiveSession.new(
      ip_address: '127.0.0.1',
      browser: browser,
      os: 'Ubuntu',
      device_type: 'desktop',
      session_private_id: 'private-id',
      created_at: time,
      updated_at: time
    )
  end

  before do
    allow(view).to receive(:s_).and_call_original
    translations.each { |msgid, translation| allow(view).to receive(:s_).with(msgid).and_return(translation) }

    render partial: 'user_settings/active_sessions/active_session', locals: { active_session: active_session }
  end

  it 'renders the session details as full sentences' do
    expect(rendered).to have_content(format(s_('ProfileSession|Last accessed on %{date}'), date: date))
    expect(rendered).to have_content(format(s_('ProfileSession|%{browser} on %{os}'), browser: 'Firefox', os: 'Ubuntu'))
    expect(rendered).to have_content(
      format(s_('ProfileSession|%{strong_start}Signed in%{strong_end} on %{date}'),
        strong_start: '', strong_end: '', date: date)
    )
  end

  it 'keeps the bold text' do
    expect(rendered).to have_css('strong', text: 'Firefox')
    expect(rendered).to have_css('strong', text: 'Ubuntu')
    expect(rendered).to have_css('strong', text: 'Signed in')
  end

  context 'when a translation changes the word order' do
    let(:translations) { { 'ProfileSession|%{browser} on %{os}' => '%{os} / %{browser}' } }

    it 'follows the order of the translation' do
      expect(rendered).to have_content('Ubuntu / Firefox')
      expect(rendered).to have_css('strong', text: 'Ubuntu')
      expect(rendered).to have_css('strong', text: 'Firefox')
    end
  end

  context 'when the browser name contains HTML' do
    let(:browser) { '<script>alert("xss")</script>' }

    it 'escapes the browser name', :skip_html_escaped_tags_check do
      expect(rendered).not_to include('<script>alert("xss")</script>')
      expect(rendered).to have_content(format(s_('ProfileSession|%{browser} on %{os}'), browser: browser, os: 'Ubuntu'))
    end
  end
end
