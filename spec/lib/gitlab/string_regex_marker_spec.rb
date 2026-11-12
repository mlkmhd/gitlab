# frozen_string_literal: true

require 'fast_spec_helper'

RSpec.describe Gitlab::StringRegexMarker, feature_category: :source_code_management do
  describe '#mark' do
    context 'with a Gitlab::UntrustedRegexp' do
      subject(:marked) do
        described_class.new(raw, rich).mark(regexp) { |text, **| ActiveSupport::SafeBuffer.new("<strong>#{text}</strong>") }
      end

      let(:raw) { 'a <b> <c> d' }
      let(:rich) { ActiveSupport::SafeBuffer.new('a &lt;b&gt; &lt;c&gt; d') }
      let(:regexp) { Gitlab::UntrustedRegexp.new('<[a-z]>') }

      it 'marks the matches' do
        expect(marked).to eq(%(a <strong>&lt;b&gt;</strong> <strong>&lt;c&gt;</strong> d))
        expect(marked).to be_html_safe
      end
    end
  end
end
