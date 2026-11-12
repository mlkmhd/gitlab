# frozen_string_literal: true

RSpec.describe Bitbucket::Error::InvalidResponse do
  describe '#initialize' do
    it 'accepts a message' do
      error = described_class.new('Expected Hash response, got String')

      expect(error.message).to eq('Expected Hash response, got String')
    end

    it 'accepts an optional http_status' do
      error = described_class.new('HTTP 401', http_status: 401)

      expect(error.message).to eq('HTTP 401')
      expect(error.http_status).to eq(401)
    end

    it 'defaults http_status to nil when not provided' do
      error = described_class.new('some error')

      expect(error.http_status).to be_nil
    end
  end

  describe '#http_status' do
    it 'returns the HTTP status code' do
      error = described_class.new('Server error', http_status: 500)

      expect(error.http_status).to eq(500)
    end
  end

  it 'is a StandardError' do
    expect(described_class.new('error')).to be_a(StandardError)
  end
end
