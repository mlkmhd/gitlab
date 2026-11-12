# frozen_string_literal: true

require 'spec_helper'

RSpec.describe AuditEvents::Streaming::Outcome, feature_category: :audit_events do
  using RSpec::Parameterized::TableSyntax

  let(:codeless_response) { Object.new }

  def http_response(code)
    instance_double(HTTParty::Response, code: code)
  end

  describe '#status_code' do
    it 'returns the response code when the response has one' do
      expect(described_class.new(response: http_response(204)).status_code).to eq(204)
    end

    it 'returns nil without a response or for a response without a code', :aggregate_failures do
      expect(described_class.new.status_code).to be_nil
      expect(described_class.new(response: codeless_response).status_code).to be_nil
    end

    it 'falls back to the status of a destination error' do
      error = AuditEvents::Streaming::Destinations::DestinationError.new(503)

      expect(described_class.new(error: error, error_category: :server_error).status_code).to eq(503)
    end
  end

  describe '#rejected?' do
    where(:code, :rejected) do
      199 | true
      200 | false
      299 | false
      300 | true
      413 | true
      503 | true
    end

    with_them do
      it 'treats only a 2xx as accepted' do
        expect(described_class.new(response: http_response(code)).rejected?).to eq(rejected)
      end
    end

    it 'is false without a status code', :aggregate_failures do
      expect(described_class.new.rejected?).to be(false)
      expect(described_class.new(response: codeless_response).rejected?).to be(false)
    end

    it 'is false for a failed delivery, which the failure path logs' do
      error = AuditEvents::Streaming::Destinations::DestinationError.new(403)

      expect(described_class.new(error: error, error_category: :auth).rejected?).to be(false)
    end
  end

  describe '#slow_or_rejected?' do
    where(:duration_s, :code, :slow_or_rejected) do
      nil   | 200 | false
      3.999 | 200 | false
      4     | 200 | true
      4.0   | 200 | true
      0.1   | 500 | true
      nil   | nil | false
      12.5  | nil | true
    end

    with_them do
      it 'is true at or past the slow threshold or on a non-2xx' do
        response = code && http_response(code)

        outcome = described_class.new(response: response, duration_s: duration_s)

        expect(outcome.slow_or_rejected?).to eq(slow_or_rejected)
      end
    end
  end

  describe '#logged_duration_s' do
    it 'rounds to the shared duration precision' do
      expect(described_class.new(duration_s: 1.23456789).logged_duration_s).to eq(1.234568)
    end

    it 'is zero when nothing was measured' do
      expect(described_class.new.logged_duration_s).to eq(0.0)
    end
  end
end
