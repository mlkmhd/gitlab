# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Gitlab::Email::Hook::AdditionalHeadersInterceptor do
  # Rails 8.1 excludes `mail` from `action_methods`, so it can no longer be called
  # directly on ActionMailer::Base. Route it through a mailer action instead.
  let(:mailer_class) do
    Class.new(ApplicationMailer) do
      def self.name
        'TestMailer'
      end

      def test_mail(headers)
        mail(headers)
      end
    end
  end

  let(:mail) do
    mailer_class.test_mail(to: 'test@mail.com', from: 'info@mail.com', body: 'hello')
  end

  before do
    mail.deliver_now
  end

  it 'adds Auto-Submitted header' do
    expect(mail.header['To'].value).to eq('test@mail.com')
    expect(mail.header['From'].value).to eq('info@mail.com')
    expect(mail.header['Auto-Submitted'].value).to eq('auto-generated')
    expect(mail.header['X-Auto-Response-Suppress'].value).to eq('All')
  end

  context 'when the same mail object is sent twice' do
    before do
      mail.deliver_now
    end

    it 'does not add the Auto-Submitted header twice' do
      expect(mail.header['Auto-Submitted'].value).to eq('auto-generated')
      expect(mail.header['X-Auto-Response-Suppress'].value).to eq('All')
    end
  end
end
