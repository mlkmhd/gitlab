# frozen_string_literal: true

require 'spec_helper'

RSpec.describe ServicePing::InternalApiAuthenticator, feature_category: :service_ping do
  let(:secret) { SecureRandom.random_bytes(Gitlab::JwtAuthenticatable::SECRET_LENGTH) }
  let(:claims) do
    {
      'iss' => described_class::JWT_ISSUER,
      'aud' => described_class::JWT_AUDIENCE,
      'sub' => 'service-ping-exporter',
      'iat' => Time.current.to_i
    }
  end

  before do
    allow(described_class).to receive(:secret).and_return(secret)
  end

  describe '.verify_api_request' do
    def headers_with(token)
      { described_class::API_HEADER => token }
    end

    it 'returns the payload of a valid token' do
      payload = described_class.verify_api_request(headers_with(JWT.encode(claims, secret, 'HS256')))

      expect(payload).to include('sub' => 'service-ping-exporter')
    end

    it 'returns nil when the header is missing' do
      expect(described_class.verify_api_request({})).to be_nil
    end

    it 'returns nil for a token signed with another secret' do
      other_secret = SecureRandom.random_bytes(Gitlab::JwtAuthenticatable::SECRET_LENGTH)

      expect(described_class.verify_api_request(headers_with(JWT.encode(claims, other_secret, 'HS256')))).to be_nil
    end

    # Time-relative claims are wrapped in procs so they resolve against Time.current
    # when the example runs, not when the file loads, otherwise they drift stale.
    [
      { 'iss' => 'gitlab' },
      { 'aud' => 'gitlab-knowledge-graph' },
      { 'sub' => '' },
      { 'iat' => nil },
      { 'iat' => -> { 6.minutes.ago.to_i } },
      { 'iat' => -> { 1.minute.from_now.to_i } },
      { 'exp' => -> { 1.minute.ago.to_i } }
    ].each do |invalid_claims|
      it "returns nil for a token with invalid claims: #{invalid_claims.keys.inspect}" do
        resolved = invalid_claims.transform_values { |value| value.respond_to?(:call) ? value.call : value }
        token = JWT.encode(claims.merge(resolved).compact, secret, 'HS256')

        expect(described_class.verify_api_request(headers_with(token))).to be_nil
      end
    end

    it 'returns nil when the secret file does not exist' do
      allow(described_class).to receive(:secret).and_raise(Errno::ENOENT)

      expect(described_class.verify_api_request(headers_with(JWT.encode(claims, secret, 'HS256')))).to be_nil
    end

    it 'returns nil and logs a warning when the secret file is not valid base64' do
      allow(described_class).to receive(:secret).and_raise(ArgumentError, 'invalid base64')

      expect(Gitlab::AppLogger).to receive(:warn).with(hash_including(Labkit::Fields::ERROR_TYPE => 'ArgumentError'))

      expect(described_class.verify_api_request(headers_with(JWT.encode(claims, secret, 'HS256')))).to be_nil
    end

    it 'returns nil and logs a warning when the secret file has the wrong length' do
      allow(described_class).to receive(:secret).and_raise(RuntimeError, 'does not contain 32 bytes')

      expect(Gitlab::AppLogger).to receive(:warn).with(hash_including(Labkit::Fields::ERROR_TYPE => 'RuntimeError'))

      expect(described_class.verify_api_request(headers_with(JWT.encode(claims, secret, 'HS256')))).to be_nil
    end
  end

  describe '.ensure_secret!' do
    let(:secret_path) { Rails.root.join('tmp/tests/.gitlab_service_ping_secret_test') }

    before do
      allow(described_class).to receive(:secret_path).and_return(secret_path)
      FileUtils.rm_f(secret_path)
    end

    after do
      FileUtils.rm_f(secret_path)
    end

    it 'writes a secret when none exists' do
      described_class.ensure_secret!

      expect(Base64.strict_decode64(File.read(secret_path)).bytesize).to eq(Gitlab::JwtAuthenticatable::SECRET_LENGTH)
    end

    it 'keeps an existing secret' do
      File.write(secret_path, 'existing')

      described_class.ensure_secret!

      expect(File.read(secret_path)).to eq('existing')
    end

    it 'logs a warning when the secret cannot be written' do
      allow(described_class).to receive(:write_secret).and_raise(Errno::EROFS)

      expect(Gitlab::AppLogger).to receive(:warn).with(hash_including(
        Labkit::Fields::LOG_MESSAGE => a_string_including(secret_path.to_s),
        Labkit::Fields::ERROR_TYPE => 'Errno::EROFS'
      ))

      described_class.ensure_secret!
    end
  end
end
