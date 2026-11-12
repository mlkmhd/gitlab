# frozen_string_literal: true

require 'fast_spec_helper'

RSpec.describe ContainerRegistry::Config, feature_category: :container_registry do
  let(:tag) { instance_double(ContainerRegistry::Tag) }
  let(:blob) { instance_double(ContainerRegistry::Blob) }

  describe '#labels' do
    context 'when config has labels' do
      let(:config_data) do
        {
          'config' => {
            'Labels' => {
              'com.example.vendor' => 'ACME Inc',
              'version' => '1.0'
            }
          }
        }
      end

      before do
        allow(blob).to receive(:data).and_return(Gitlab::Json.pretty_generate(config_data))
      end

      it 'returns the labels hash' do
        config = described_class.new(tag, blob)
        expect(config.labels).to eq(config_data['config']['Labels'])
      end
    end

    context 'when config has no labels' do
      let(:config_data) { { 'config' => {} } }

      before do
        allow(blob).to receive(:data).and_return(Gitlab::Json.pretty_generate(config_data))
      end

      it 'returns an empty hash' do
        config = described_class.new(tag, blob)
        expect(config.labels).to eq({})
      end
    end

    context 'when blob data is nil' do
      let(:config_data) { nil }

      before do
        allow(blob).to receive(:data).and_return(Gitlab::Json.pretty_generate(config_data))
      end

      it 'returns an empty hash' do
        config = described_class.new(tag, blob)

        expect(config.labels).to eq({})
      end
    end

    [
      { 'config' => 'x' },
      { 'config' => [1] },
      { 'config' => { 'Labels' => 'x' } },
      { 'config' => { 'Labels' => { 'a' => 1 } } },
      %w[not a hash]
    ].each do |config_data|
      context "when the config data is #{config_data.inspect}" do
        before do
          allow(blob).to receive(:data).and_return(config_data.to_json)
        end

        it 'returns an empty hash' do
          expect(described_class.new(tag, blob).labels).to eq({})
        end
      end
    end
  end
end
