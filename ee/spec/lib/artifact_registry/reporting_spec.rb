# frozen_string_literal: true

require 'spec_helper'

RSpec.describe ArtifactRegistry::Reporting, :aggregate_failures, feature_category: :artifact_registry do
  subject(:reporting) { described_class.new(base_url: base_url, service_credential: service_credential) }

  let(:base_url) { 'https://artifact-registry.example.test' }
  let(:service_credential) { instance_double(ArtifactRegistry::ServiceCredential, token: 'svc-token') }

  describe '#log_error' do
    before do
      allow(Gitlab::ErrorTracking).to receive(:log_exception)
    end

    it 'logs the redacted error with the request identifiers and the caller context' do
      error = ArtifactRegistry::Errors::ApiError.new('rejected svc-token', status: 404, request_id: 'req-1')

      Labkit::Correlation::CorrelationId.use_id('corr-1') do
        reporting.log_error(error, slug: 'my-group')
      end

      expect(Gitlab::ErrorTracking).to have_received(:log_exception).with(
        an_instance_of(ArtifactRegistry::Errors::ApiError).and(having_attributes(message: 'rejected [REDACTED]')),
        {
          url: 'https://artifact-registry.example.test',
          correlation_id: 'corr-1',
          status: 404,
          request_id: 'req-1',
          slug: 'my-group'
        }
      )
    end
  end

  describe '#raise_terminal' do
    before do
      allow(Gitlab::ErrorTracking).to receive(:log_exception)
      allow(Labkit::Correlation::CorrelationId).to receive(:current_id).and_return('corr-1')
    end

    def raise_unavailable(**options)
      reporting.raise_terminal(ArtifactRegistry::Errors::UnavailableError, 'AR rejected svc-token', :get, **options)
    end

    def raise_unavailable_while_rescuing
      raise StandardError, 'reporting side'
    rescue StandardError
      raise_unavailable
    end

    it 'reports the redacted error and raises it with the given cause' do
      cause = Faraday::TimeoutError.new('timed out')

      expect { raise_unavailable(cause: cause, status: 503, slug: 'my-group') }
        .to raise_error(ArtifactRegistry::Errors::UnavailableError, 'AR rejected [REDACTED]') do |error|
          expect(error.status).to eq(503)
          expect(error.cause).to be(cause)
        end

      expect(Gitlab::ErrorTracking).to have_received(:log_exception).with(
        an_instance_of(ArtifactRegistry::Errors::UnavailableError)
          .and(having_attributes(message: 'AR rejected [REDACTED]')),
        {
          url: 'https://artifact-registry.example.test',
          method: :get,
          correlation_id: 'corr-1',
          status: 503,
          slug: 'my-group'
        }
      )
    end

    it 'raises with no cause, even inside a rescue, when none is given' do
      expect { raise_unavailable_while_rescuing }.to raise_error(ArtifactRegistry::Errors::UnavailableError) do |error|
        expect(error.cause).to be_nil
      end
    end
  end

  describe '#report_attempt' do
    before do
      allow(Gitlab::ErrorTracking).to receive(:log_exception)
    end

    it 'reports the redacted failure with the attempt and the correlation id' do
      error = Faraday::ConnectionFailed.new('refused svc-token')

      Labkit::Correlation::CorrelationId.use_id('corr-1') do
        reporting.report_attempt(error, url: 'https://artifact-registry.example.test/api/v1/my-group',
          method: :get, status: 502)
      end

      expect(Gitlab::ErrorTracking).to have_received(:log_exception).with(
        an_instance_of(Faraday::ConnectionFailed).and(having_attributes(message: 'refused [REDACTED]')),
        {
          url: 'https://artifact-registry.example.test/api/v1/my-group',
          method: :get,
          correlation_id: 'corr-1',
          status: 502
        }
      )
    end
  end

  describe '#redacted_snippet' do
    it 'redacts the service token and bearer credentials and bounds the length' do
      snippet = reporting.redacted_snippet("Bearer user-jwt svc-token #{'x' * 300}")

      expect(snippet).to start_with('Bearer [REDACTED] [REDACTED] xxx')
      expect(snippet.length).to eq(ArtifactRegistry::Redaction::MAX_SNIPPET)
    end

    it 'still redacts bearer credentials when the service token cannot be read' do
      allow(service_credential).to receive(:token).and_raise(ArtifactRegistry::Errors::AuthorizationError)

      expect(reporting.redacted_snippet('Bearer user-jwt')).to eq('Bearer [REDACTED]')
    end

    context 'when the first service token read fails' do
      before do
        allow(service_credential).to receive(:token).and_raise(ArtifactRegistry::Errors::AuthorizationError)
        reporting.redacted_snippet('warm-up')
        allow(service_credential).to receive(:token).and_return('svc-token')
      end

      it 'redacts the service token once it can be read' do
        expect(reporting.redacted_snippet('upstream rejected svc-token')).to eq('upstream rejected [REDACTED]')
      end
    end
  end
end
