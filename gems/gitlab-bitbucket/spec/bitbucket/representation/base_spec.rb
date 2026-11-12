# frozen_string_literal: true

RSpec.describe Bitbucket::Representation::Base do
  describe '#initialize' do
    context 'when raw is a Hash' do
      it 'assigns raw to the instance variable' do
        raw = { 'key' => 'value' }
        instance = described_class.new(raw)

        expect(instance.raw).to eq(raw)
      end
    end

    context 'when raw is a String' do
      it 'raises InvalidResponse error' do
        expect { described_class.new('<html>Error</html>') }
          .to raise_error(Bitbucket::Error::InvalidResponse, /Expected Hash response, got String/)
      end

      it 'includes the response body in the error message' do
        expect { described_class.new('<html>Unauthorized</html>') }
          .to raise_error(Bitbucket::Error::InvalidResponse, %r{<html>Unauthorized</html>})
      end
    end

    context 'when raw is nil' do
      it 'raises InvalidResponse error' do
        expect { described_class.new(nil) }
          .to raise_error(Bitbucket::Error::InvalidResponse, /Expected Hash response, got NilClass/)
      end
    end

    context 'when raw is an Array' do
      it 'raises InvalidResponse error' do
        expect { described_class.new([1, 2, 3]) }
          .to raise_error(Bitbucket::Error::InvalidResponse, /Expected Hash response, got Array/)
      end
    end
  end

  describe '.decorate' do
    it 'creates instances for each entry' do
      entries = [{ 'a' => 1 }, { 'b' => 2 }]
      result = described_class.decorate(entries)

      expect(result.size).to eq(2)
      expect(result).to all(be_a(described_class))
    end

    it 'raises InvalidResponse if any entry is not a Hash' do
      entries = [{ 'a' => 1 }, 'not a hash']

      expect { described_class.decorate(entries) }
        .to raise_error(Bitbucket::Error::InvalidResponse)
    end
  end

  describe '#present?' do
    it 'returns true for non-empty hash' do
      instance = described_class.new({ 'key' => 'value' })

      expect(instance.present?).to be true
    end

    it 'returns false for empty hash' do
      instance = described_class.new({})

      expect(instance.present?).to be false
    end
  end
end
