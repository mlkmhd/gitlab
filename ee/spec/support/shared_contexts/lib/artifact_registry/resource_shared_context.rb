# frozen_string_literal: true

RSpec.shared_context 'with an Artifact Registry resource' do
  let(:base_url) { 'https://artifact-registry.example.test' }
  let(:slug) { 'my-group' }
  let(:name) { 'my-repo' }
  let(:token) { 'ar-bootstrap-token-value' }
  let(:jwt_credential) { 'fake-jwt-header-segment.fake-jwt-payload-segment.fake-jwt-signature-segment' }
  let(:current_user) { instance_double(User) }
  let(:token_exchange) { instance_double(ArtifactRegistry::TokenExchange, token_for: token) }
  let(:json_headers) { { 'Content-Type' => 'application/json' } }
  let(:service_credential) { ArtifactRegistry::ServiceCredential.new }
  let(:reporting) { ArtifactRegistry::Reporting.new(base_url: base_url, service_credential: service_credential) }

  let(:transport) do
    ArtifactRegistry::Transport.new(
      base_url: base_url,
      current_user: current_user,
      organization: nil,
      token_exchange: token_exchange,
      service_credential: service_credential,
      reporting: reporting
    )
  end

  let(:client) { described_class.new(transport: transport, reporting: reporting) }

  let(:repository_url) { "#{base_url}/api/v1/#{slug}/repositories/#{name}" }

  let(:retry_options) do
    ArtifactRegistry::Transport::RETRY_OPTIONS.merge(interval: 0, interval_randomness: 0, backoff_factor: 0)
  end

  def expect_auth_failure_reported_once(status)
    expect(Gitlab::ErrorTracking).to have_received(:log_exception).once
    expect(Gitlab::ErrorTracking).to have_received(:log_exception)
      .with(instance_of(described_class::AuthorizationError), hash_including(status: status))
  end

  def error_envelope(code: 'error_code', message: 'something went wrong', request_id: 'req-envelope-id')
    { error: { code: code, message: message, request_id: request_id } }
  end
end
