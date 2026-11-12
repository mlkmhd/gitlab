# frozen_string_literal: true

require 'fast_spec_helper'

RSpec.describe ContainerRegistry::MetadataMap, feature_category: :container_registry do
  describe '.sanitize' do
    [nil, 'x', ['a'], 1].each do |input|
      it "returns an empty hash for #{input.inspect}" do
        expect(described_class.sanitize(input)).to eq({})
      end
    end

    it 'returns string maps unchanged' do
      expect(described_class.sanitize('a' => 'b')).to eq('a' => 'b')
    end

    it 'drops nil values' do
      expect(described_class.sanitize('a' => nil, 'b' => 'c')).to eq('b' => 'c')
    end

    it 'returns an empty hash when a value is not a string' do
      expect(described_class.sanitize('a' => 1, 'b' => 'c')).to eq({})
      expect(described_class.sanitize('a' => { 'b' => 'c' })).to eq({})
    end

    it 'keeps the first 25 entries by sorted key' do
      map = (1..30).to_a.reverse.to_h { |i| [format('key%02d', i), 'v'] }

      expect(described_class.sanitize(map).keys).to eq((1..25).map { |i| format('key%02d', i) })
    end

    it 'truncates values to 4096 bytes' do
      expect(described_class.sanitize('a' => 'x' * 5000)['a'].bytesize).to eq(4096)
    end

    it 'leaves a value of exactly 4096 bytes alone' do
      expect(described_class.sanitize('a' => 'x' * 4096)['a'].bytesize).to eq(4096)
    end

    it 'does not leave a broken multibyte character after truncation' do
      value = described_class.sanitize('a' => '€' * 2000)['a']

      expect(value).to be_valid_encoding
      expect(value.bytesize).to eq(4095)
    end

    it 'replaces invalid UTF-8 bytes in a value with U+FFFD' do
      value = "x\xFF"
      expect(value).not_to be_valid_encoding

      result = described_class.sanitize('a' => value)

      expect(result).to eq('a' => "x\uFFFD")
      expect(result['a']).to be_valid_encoding
    end

    it 'replaces invalid UTF-8 bytes in a key with U+FFFD' do
      key = "k\xFF"
      expect(key).not_to be_valid_encoding

      result = described_class.sanitize(key => 'v')

      expect(result).to eq("k\uFFFD" => 'v')
      expect(result.each_key.first).to be_valid_encoding
    end

    it 'returns a map that can be serialized to JSON' do
      result = described_class.sanitize("k\xFF" => "v\xFE")

      expect { Gitlab::Json.dump(result) }.not_to raise_error
    end
  end
end
