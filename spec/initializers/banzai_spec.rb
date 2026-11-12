# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'Banzai configuration', feature_category: :markdown do
  using RSpec::Parameterized::TableSyntax

  describe 'timeout_disabled' do
    subject(:timeout_disabled) { Banzai.configuration.timeout_disabled }

    where(:env_value, :result) do
      nil     | false
      'false' | false
      'true'  | true
    end

    with_them do
      before do
        stub_env('GITLAB_DISABLE_MARKDOWN_TIMEOUT', env_value)
      end

      it { is_expected.to be(result) }
    end
  end

  describe 'with_timeout' do
    it 'runs the block under `Gitlab::RenderTimeout` with the same budget in the foreground and background' do
      expect(Gitlab::RenderTimeout).to receive(:timeout).with(foreground: 3, background: 3).and_call_original

      expect(Banzai.configuration.with_timeout(3) { :rendered }).to eq(:rendered)
    end

    it 'raises `Timeout::Error` when the budget runs out' do
      allow(Gitlab::RenderTimeout).to receive(:timeout).and_raise(Timeout::Error)

      expect { Banzai.configuration.with_timeout(3) { :rendered } }.to raise_error(Timeout::Error)
    end
  end

  describe 'translate' do
    Banzai::Configuration::MESSAGE_KEYS.each do |key, names|
      it "defines `#{key}`, interpolating #{names.any? ? names.join(', ') : 'nothing'}" do
        values = names.index_with { |name| "<#{name}>" }
        message = Banzai.configuration.translate(key, **values)

        expect(message).to be_present
        values.each_value { |value| expect(message).to include(value) }
      end
    end

    it 'translates in the current locale' do
      Gitlab::I18n.with_locale(:de) do
        expect(Banzai.configuration.translate(:task_item_default_label)).to eq(_('Check option'))
      end
    end

    it 'raises for an unknown key' do
      expect { Banzai.configuration.translate(:unknown) }.to raise_error(KeyError)
    end
  end

  describe 'track_exception' do
    it 'reports to `Gitlab::ErrorTracking` with the extra context' do
      exception = Timeout::Error.new

      expect(Gitlab::ErrorTracking).to receive(:track_exception).with(exception, project_id: 1, class_name: 'Filter')

      Banzai.configuration.track_exception(exception, project_id: 1, class_name: 'Filter')
    end
  end
end
