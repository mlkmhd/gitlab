# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Gitlab::Metrics::AuditEventStreamingSlis, :prometheus, feature_category: :audit_events do
  using RSpec::Parameterized::TableSyntax

  let(:labels) { described_class::LABELS }

  before do
    described_class.initialize_slis!
  end

  describe '.initialize_slis!' do
    it 'initializes the dispatch error-rate and apdex SLIs', :aggregate_failures do
      expect(Gitlab::Metrics::Sli::ErrorRate)
        .to receive(:initialize_sli).with(described_class::DISPATCH_SLI, [labels])
      expect(Gitlab::Metrics::Sli::Apdex)
        .to receive(:initialize_sli).with(described_class::DISPATCH_SLI, [labels])

      described_class.initialize_slis!
    end

    it 'pre-creates the plain publish counters at zero so their series exist', :aggregate_failures do
      expect(publish_count).to eq(0)
      expect(consumer_unreachable_count).to eq(0)
      expect(dispatch_destination_error_count).to eq(0)
      described_class::FALLBACK_REASONS.each { |reason| expect(fallback_count(reason)).to eq(0) }
    end

    it 'names the dispatch SLI so it emits the documented gitlab_sli_ series' do
      # The framework derives gitlab_sli_<name>_total / _error_total /
      # _apdex_total series from this name; it is the contract with the docs
      # table and the runbooks catalog.
      expect(described_class::DISPATCH_SLI).to eq(:audit_event_streaming_nats_dispatch)
    end

    it 'does not pre-create delivery series outside Sidekiq, where nothing delivers' do
      expect(described_class.delivery_counter.values).to be_empty
    end

    context 'when running in Sidekiq' do
      before do
        allow(Gitlab::Runtime).to receive(:sidekiq?).and_return(true)
        described_class.initialize_slis!
      end

      it 'pre-creates a zero delivery series per category for every outcome and error category', :aggregate_failures do
        destination_error_categories = %i[
          timeout connection auth not_found rate_limited client_error server_error invalid_config
        ]

        expected = AuditEvents::Streaming::Destinations::BY_CATEGORY.keys.flat_map do |category|
          [
            labels.merge(destination_category: category, outcome: :success, error_category: :none),
            labels.merge(destination_category: category, outcome: :internal_error, error_category: :internal_error),
            *destination_error_categories.map do |error_category|
              labels.merge(destination_category: category, outcome: :destination_error, error_category: error_category)
            end
          ]
        end

        series = described_class.delivery_counter.values.transform_values(&:get)

        expect(series).to include(expected.index_with(0.0))
        expect(series.size).to eq(expected.size)
      end
    end
  end

  describe '.record_delivery' do
    it 'increments the delivery counter by the event count under the outcome labels' do
      expect do
        described_class.record_delivery(category: 'http', outcome: :destination_error, error_category: :auth, count: 3)
      end
        .to change { delivery_count('http', :destination_error, :auth) }.by(3)
        .and not_change { delivery_count('http', :success, :none) }
    end

    it 'emits a plain counter name without the gitlab_sli_ prefix' do
      expect(described_class.delivery_counter.name).to eq(:gitlab_audit_event_streaming_deliveries_total)
    end
  end

  describe '.observe_delivery_duration' do
    it 'observes the duration under the category and outcome labels' do
      expect(described_class.delivery_duration_histogram)
        .to receive(:observe).with(labels.merge(destination_category: 'aws', outcome: :destination_error), 0.3)

      described_class.observe_delivery_duration(category: 'aws', outcome: :destination_error, seconds: 0.3)
    end

    it 'ignores a delivery that has no measured duration' do
      expect(described_class.delivery_duration_histogram).not_to receive(:observe)

      described_class.observe_delivery_duration(category: 'aws', outcome: :internal_error, seconds: nil)
    end
  end

  describe '.delivery_duration_histogram' do
    it 'is registered with the documented name and buckets', :aggregate_failures do
      histogram = described_class.delivery_duration_histogram
      described_class.observe_delivery_duration(category: 'http', outcome: :success, seconds: 0.3)

      expect(histogram).to be_a(Prometheus::Client::Histogram)
      expect(histogram.name).to eq(:gitlab_audit_event_streaming_delivery_duration_seconds)
      expect(histogram.get(labels.merge(destination_category: 'http', outcome: :success))).to eq(
        {
          0.05 => 0, 0.1 => 0, 0.25 => 0, 0.5 => 1, 1 => 1, 2 => 1, 4 => 1,
          8 => 1, 16 => 1, 30 => 1, 60 => 1, 120 => 1, 300 => 1
        }
      )
    end
  end

  describe '.record_publish' do
    it 'counts a publish attempt without a fallback when NATS acknowledged' do
      expect { described_class.record_publish(fallback: false) }
        .to change { publish_count }.by(1)
        .and not_change { fallback_count(:timeout) }
    end

    it 'counts both an attempt and a reason-labelled fallback when the publish fell back' do
      expect { described_class.record_publish(fallback: true, reason: :timeout) }
        .to change { publish_count }.by(1)
        .and change { fallback_count(:timeout) }.by(1)
        .and not_change { fallback_count(:connection_lost) }
    end

    it 'labels an unknown or missing reason as unexpected' do
      expect { described_class.record_publish(fallback: true, reason: :bogus) }
        .to change { fallback_count(:unexpected) }.by(1)
      expect { described_class.record_publish(fallback: true) }
        .to change { fallback_count(:unexpected) }.by(1)
    end

    it 'emits plain counter names without the gitlab_sli_ prefix', :aggregate_failures do
      expect(described_class.publish_counter.name).to eq(:gitlab_audit_event_streaming_nats_publish_total)
      expect(described_class.fallback_counter.name)
        .to eq(:gitlab_audit_event_streaming_nats_publish_fallback_total)
    end
  end

  describe '.record_publish_duration' do
    it 'observes the duration on the publish-duration histogram' do
      expect(described_class.publish_duration_histogram).to receive(:observe).with(labels, 0.25)

      described_class.record_publish_duration(0.25)
    end

    it 'ignores nil or negative durations', :aggregate_failures do
      expect(described_class).not_to receive(:publish_duration_histogram)

      described_class.record_publish_duration(nil)
      described_class.record_publish_duration(-1)
    end
  end

  describe '.record_consumer_unreachable' do
    it 'increments the consumer-unreachable counter' do
      expect { described_class.record_consumer_unreachable }
        .to change { consumer_unreachable_count }.by(1)
    end

    it 'emits a plain counter name without the gitlab_sli_ prefix' do
      expect(described_class.consumer_unreachable_counter.name)
        .to eq(:gitlab_audit_event_streaming_nats_consumer_unreachable_total)
    end
  end

  describe '.record_dispatch' do
    where(:result, :expected_error) do
      :success | false
      :failure | true
    end

    with_them do
      it 'maps the dispatch result to the error flag on the dispatch SLI' do
        expect(described_class.dispatch_error_rate).to receive(:increment).with(labels: labels, error: expected_error)

        described_class.record_dispatch(result: result)
      end
    end
  end

  describe '.record_dispatch_destination_error' do
    it 'increments the destination-error counter' do
      expect { described_class.record_dispatch_destination_error }
        .to change { dispatch_destination_error_count }.by(1)
    end

    it 'does not touch the dispatch SLI error rate (degradation, not an error)' do
      expect(described_class.dispatch_error_rate).not_to receive(:increment)

      described_class.record_dispatch_destination_error
    end

    it 'emits a plain counter name without the gitlab_sli_ prefix' do
      expect(described_class.dispatch_destination_error_counter.name)
        .to eq(:gitlab_audit_event_streaming_nats_dispatch_destination_error_total)
    end
  end

  describe '.observe_fetch_lag' do
    it 'observes the age labelled by whether the message was redelivered' do
      expect(described_class.fetch_lag_histogram).to receive(:observe).with(labels.merge(redelivered: 'true'), 7200.0)

      described_class.observe_fetch_lag(7200.0, redelivered: true)
    end

    it 'ignores nil and negative ages' do
      expect(described_class).not_to receive(:fetch_lag_histogram)

      described_class.observe_fetch_lag(nil, redelivered: false)
      described_class.observe_fetch_lag(-1, redelivered: false)
    end
  end

  describe '.record_permanent_failure' do
    it 'counts the dropped events by destination and error category', :aggregate_failures do
      auth_labels = labels.merge(destination_category: 'gcp', error_category: 'auth')
      other_labels = labels.merge(destination_category: 'http', error_category: 'auth')

      record = -> do
        described_class.record_permanent_failure(destination_category: :gcp, error_category: :auth, event_count: 3)
      end

      expect(&record)
        .to change { described_class.permanent_failure_events_counter.get(auth_labels) }.by(3)
        .and not_change { described_class.permanent_failure_events_counter.get(other_labels) }
    end

    it 'emits a plain counter name without the gitlab_sli_ prefix' do
      expect(described_class.permanent_failure_events_counter.name)
        .to eq(:gitlab_audit_event_streaming_nats_permanent_failure_events_total)
    end
  end

  describe '.record_max_delivery' do
    it 'increments the max-deliveries counter for the consumer only', :aggregate_failures do
      consumer_labels = labels.merge(consumer: 'audit_streaming_consumer_3')
      other_labels = labels.merge(consumer: 'audit_streaming_consumer_4')

      expect { described_class.record_max_delivery(consumer: 'audit_streaming_consumer_3') }
        .to change { described_class.max_deliveries_counter.get(consumer_labels) }.by(1)
        .and not_change { described_class.max_deliveries_counter.get(other_labels) }
    end

    it 'emits a plain counter name without the gitlab_sli_ prefix' do
      expect(described_class.max_deliveries_counter.name)
        .to eq(:gitlab_audit_event_streaming_nats_max_deliveries_total)
    end
  end

  describe '.observe_lag' do
    it 'observes the lag and scores the apdex as satisfied when under target', :aggregate_failures do
      expect(described_class.lag_histogram).to receive(:observe).with(labels, 1.5)
      expect(described_class.dispatch_lag_apdex).to receive(:increment).with(labels: labels, success: true)

      described_class.observe_lag(1.5)
    end

    it 'scores the apdex as unsatisfied when lag exceeds the target' do
      over_target = described_class::LAG_APDEX_TARGET_SECONDS + 1

      expect(described_class.dispatch_lag_apdex).to receive(:increment).with(labels: labels, success: false)

      described_class.observe_lag(over_target)
    end

    it 'ignores nil lag', :aggregate_failures do
      expect(described_class).not_to receive(:lag_histogram)
      expect(described_class).not_to receive(:dispatch_lag_apdex)

      described_class.observe_lag(nil)
    end

    it 'drops a negative lag with a debug log instead of observing it', :aggregate_failures do
      expect(Gitlab::AppJsonLogger).to receive(:debug).with(hash_including(lag_seconds: -1))
      expect(described_class.lag_histogram).not_to receive(:observe)

      described_class.observe_lag(-1)
    end
  end

  describe '.lag_histogram' do
    it 'is registered with the documented name and buckets', :aggregate_failures do
      histogram = described_class.lag_histogram

      expect(histogram).to be_a(Prometheus::Client::Histogram)
      expect(histogram.name).to eq(described_class::LAG_HISTOGRAM)
      expect(histogram.instance_variable_get(:@buckets)).to eq(described_class::LAG_BUCKETS)
    end
  end

  describe '.fetch_lag_histogram' do
    it 'is registered with the documented name and buckets', :aggregate_failures do
      histogram = described_class.fetch_lag_histogram

      expect(histogram).to be_a(Prometheus::Client::Histogram)
      expect(histogram.name).to eq(described_class::FETCH_LAG_HISTOGRAM)
      expect(histogram.instance_variable_get(:@buckets)).to eq(described_class::FETCH_LAG_BUCKETS)
    end
  end

  describe '.publish_duration_histogram' do
    it 'is registered with the documented name and buckets', :aggregate_failures do
      histogram = described_class.publish_duration_histogram

      expect(histogram).to be_a(Prometheus::Client::Histogram)
      expect(histogram.name).to eq(described_class::PUBLISH_DURATION_HISTOGRAM)
      expect(histogram.instance_variable_get(:@buckets)).to eq(described_class::PUBLISH_DURATION_BUCKETS)
    end
  end

  def publish_count
    described_class.publish_counter.get(labels)
  end

  def fallback_count(reason)
    described_class.fallback_counter.get(labels.merge(reason: reason))
  end

  def consumer_unreachable_count
    described_class.consumer_unreachable_counter.get(labels)
  end

  def dispatch_destination_error_count
    described_class.dispatch_destination_error_counter.get(labels)
  end

  def delivery_count(category, outcome, error_category)
    described_class.delivery_counter.get(
      labels.merge(destination_category: category, outcome: outcome, error_category: error_category)
    )
  end
end
