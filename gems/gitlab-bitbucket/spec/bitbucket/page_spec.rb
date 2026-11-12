# frozen_string_literal: true

RSpec.describe Bitbucket::Page do
  let(:response) { { 'values' => [{ 'username' => 'Ben' }], 'pagelen' => 2, 'next' => '' } }

  before do
    # Ensure class is loaded before Page tries to camelize+const_get it
    Bitbucket::Representation::User.new({})
  end

  describe '#items' do
    it 'returns collection of needed objects' do
      page = described_class.new(response, :user)

      expect(page.items.first).to be_a(Bitbucket::Representation::User)
      expect(page.items.count).to eq(1)
    end
  end

  describe '#attrs' do
    it 'returns attributes' do
      page = described_class.new(response, :user)

      expect(page.attrs.keys).to include(:pagelen, :next)
    end
  end

  describe '#next?' do
    it 'returns true' do
      page = described_class.new(response, :user)

      expect(page.next?).to be_truthy
    end

    it 'returns false' do
      response['next'] = nil
      page = described_class.new(response, :user)

      expect(page.next?).to be_falsey
    end
  end

  describe '#next' do
    it 'returns next attribute' do
      page = described_class.new(response, :user)

      expect(page.next).to eq('')
    end
  end

  describe 'when raw is not a Hash' do
    context 'when raw is a String (e.g., HTML error page)' do
      it 'raises InvalidResponse error' do
        expect { described_class.new('<html>Unauthorized</html>', :user) }
          .to raise_error(Bitbucket::Error::InvalidResponse, /Expected Hash response, got String/)
      end

      it 'includes the response body in the error message' do
        expect { described_class.new('<html>401 Unauthorized</html>', :user) }
          .to raise_error(Bitbucket::Error::InvalidResponse, %r{<html>401 Unauthorized</html>})
      end
    end

    context 'when raw is nil' do
      it 'raises InvalidResponse error' do
        expect { described_class.new(nil, :user) }
          .to raise_error(Bitbucket::Error::InvalidResponse, /Expected Hash response, got NilClass/)
      end
    end

    context 'when raw is an Array' do
      it 'raises InvalidResponse error' do
        expect { described_class.new([1, 2, 3], :user) }
          .to raise_error(Bitbucket::Error::InvalidResponse, /Expected Hash response, got Array/)
      end
    end
  end
end
