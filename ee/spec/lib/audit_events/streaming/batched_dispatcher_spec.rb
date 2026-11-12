# frozen_string_literal: true

require 'spec_helper'

RSpec.describe AuditEvents::Streaming::BatchedDispatcher, feature_category: :audit_events do
  using RSpec::Parameterized::TableSyntax

  let_it_be(:group) { create(:group) }
  let_it_be(:audit_event) { create(:audit_events_group_audit_event, group_id: group.id) }

  let(:event_name) { 'audit_operation' }
  let(:outcome_class) { AuditEvents::Streaming::Outcome }
  let(:delivered) { outcome_class.new }
  let(:stream_destination) do
    instance_double(AuditEvents::Streaming::Destinations::HttpStreamDestination, deliver_batch: delivered)
  end

  let(:payload) do
    {
      'schema_version' => 1,
      'id' => audit_event.id.to_s,
      'event_name' => event_name,
      'group_id' => group.id,
      'namespace_ancestor_ids' => [group.id],
      'project_namespace' => false,
      'event' => audit_event.as_json(methods: [:root_group_entity_id, :stream_id])
    }
  end

  subject(:dispatcher) { described_class.new(group.id, [payload]) }

  before do
    stub_licensed_features(external_audit_events: true)
    stub_feature_flags(audit_event_streaming_nats_shadow_mode: false)
  end

  context 'with an active group destination' do
    let_it_be(:destination) do
      create(:audit_events_group_external_streaming_destination, :http, group: group)
    end

    before do
      allow(AuditEvents::Streaming::Destinations::HttpStreamDestination)
        .to receive(:for_batch).with(destination).and_return(stream_destination)
    end

    it 'dispatches the batch to the destination and records circuit-breaker success' do
      expect(stream_destination).to receive(:deliver_batch) do |bodies|
        expect(bodies.size).to eq(1)
        expect(bodies.first).to include('id' => audit_event.id.to_s, 'event_type' => event_name)
        delivered
      end
      expect(AuditEvents::Streaming::CircuitBreaker).to receive(:record_success).with(destination)

      expect(dispatcher.execute).to eq(:delivered)
    end

    it 'sends multiple events as a single batched request (not per-event)' do
      expect(stream_destination).to receive(:deliver_batch).once do |bodies|
        expect(bodies.size).to eq(2)
      end

      described_class.new(group.id, [payload, payload]).execute
    end

    context 'when the delivery is fast and accepted' do
      let(:response) { instance_double(HTTParty::Response, code: 200) }

      before do
        allow(stream_destination).to receive(:deliver_batch)
          .and_return(outcome_class.new(response: response, duration_s: 0.3))
      end

      it 'does not log at info' do
        expect(::Gitlab::AppLogger).not_to receive(:info)
          .with(hash_including(message: 'Audit event delivery slow or rejected'))

        dispatcher.execute
      end
    end

    context 'when the delivery is slow' do
      let(:response) { instance_double(HTTParty::Response, code: 200) }

      before do
        allow(stream_destination).to receive(:deliver_batch)
          .and_return(outcome_class.new(response: response, duration_s: 4.2))
      end

      it 'logs the destination, root namespace, batch size, duration and status at info' do
        expect(::Gitlab::AppLogger).to receive(:info).with(
          message: 'Audit event delivery slow or rejected',
          destination_id: destination.id,
          destination_category: 'http',
          Labkit::Fields::GL_ROOT_NAMESPACE_ID => group.id,
          batch_size: 1,
          Labkit::Fields::DURATION_S => 4.2,
          Labkit::Fields::HTTP_STATUS_CODE => 200,
          error_category: nil
        )

        dispatcher.execute
      end
    end

    context 'when the delivery is slow and the destination rejects it with the flag on' do
      let(:error) { AuditEvents::Streaming::Destinations::DestinationError.new(503) }

      before do
        allow(stream_destination).to receive(:deliver_batch)
          .and_return(outcome_class.new(error: error, error_category: :server_error, duration_s: 6.0))
      end

      it 'logs the status carried by the error at info' do
        expect(::Gitlab::AppLogger).to receive(:info).with(
          hash_including(
            message: 'Audit event delivery slow or rejected',
            Labkit::Fields::HTTP_STATUS_CODE => 503,
            Labkit::Fields::DURATION_S => 6.0,
            error_category: :server_error
          )
        )

        dispatcher.execute
      end
    end

    context 'when the delivery is fast but rejected' do
      let(:response) { instance_double(HTTParty::Response, code: 413) }

      before do
        allow(stream_destination).to receive(:deliver_batch)
          .and_return(outcome_class.new(response: response, duration_s: 0.3))
      end

      it 'logs the status at info' do
        expect(::Gitlab::AppLogger).to receive(:info).with(
          hash_including(
            message: 'Audit event delivery slow or rejected',
            Labkit::Fields::HTTP_STATUS_CODE => 413,
            Labkit::Fields::DURATION_S => 0.3
          )
        )

        dispatcher.execute
      end
    end

    context 'when shadow mode is enabled' do
      before do
        stub_feature_flags(audit_event_streaming_nats_shadow_mode: true)
        allow(dispatcher).to receive(:sleep)
      end

      it 'skips the real delivery but still reports success' do
        expect(stream_destination).not_to receive(:deliver_batch)
        expect(dispatcher).to receive(:sleep).with(described_class::SHADOW_LATENCY)

        expect(dispatcher.execute).to eq(:delivered)
      end

      it 'does not touch the shared circuit breaker (no real delivery happened)' do
        expect(AuditEvents::Streaming::CircuitBreaker).not_to receive(:record_success)

        dispatcher.execute
      end
    end

    context 'when the destination has filters (N+1 guard)' do
      let(:filtered_event_name) { 'member_created' }
      let(:filtered_payload) { payload.merge('event_name' => filtered_event_name) }

      before do
        create(:audit_events_group_event_type_filters,
          external_streaming_destination: destination, audit_event_type: filtered_event_name)
        create(:audit_events_streaming_group_namespace_filters, external_streaming_destination: destination)
        allow(stream_destination).to receive(:deliver_batch).and_return(delivered)
      end

      it 'does not issue additional filter queries as the batch grows' do
        control = ActiveRecord::QueryRecorder.new { described_class.new(group.id, [filtered_payload]).execute }

        expect { described_class.new(group.id, [filtered_payload, filtered_payload, filtered_payload]).execute }
          .not_to exceed_query_limit(control)
      end
    end

    context 'when loading destinations' do
      it 'caps group destinations at the per-entity limit (defends against drift)' do
        relation = AuditEvents::Group::ExternalStreamingDestination.where(id: destination.id)
        allow(relation).to receive_messages(active: relation, preload_filters: relation)
        allow_next_found_instance_of(Group) do |group_instance|
          allow(group_instance).to receive(:external_audit_event_streaming_destinations).and_return(relation)
        end
        allow(stream_destination).to receive(:deliver_batch).and_return(delivered)

        expect(relation).to receive(:limit).with(described_class::MAX_DESTINATIONS).and_call_original

        dispatcher.execute
      end
    end

    context 'when the destination is circuit-broken' do
      before do
        allow(AuditEvents::Streaming::CircuitBreaker).to receive(:reject_open).and_return([])
      end

      it 'does not dispatch' do
        expect(AuditEvents::Streaming::Destinations::HttpStreamDestination).not_to receive(:for_batch)

        dispatcher.execute
      end
    end

    context 'when dispatch fails with a permanent error' do
      where(:error, :error_category) do
        URI::InvalidURIError.new      | :invalid_config
        StandardError.new('HTTP 401') | :auth
        StandardError.new('HTTP 404') | :not_found
        StandardError.new('HTTP 415') | :client_error
      end

      with_them do
        before do
          allow(stream_destination).to receive(:deliver_batch)
            .and_return(outcome_class.new(error: error, error_category: error_category))
        end

        it 'records the failure and the dropped events, and reports the batch as delivered', :aggregate_failures do
          expect(::Gitlab::ErrorTracking).to receive(:log_exception)
            .with(error, hash_including(error_category: error_category, redeliver: false, event_count: 1))
          expect(AuditEvents::Streaming::CircuitBreaker).to receive(:record_failure).with(destination)
          expect(::Gitlab::Metrics::AuditEventStreamingSlis).to receive(:record_permanent_failure)
            .with(destination_category: 'http', error_category: error_category, event_count: 1)

          expect(dispatcher.execute).to eq(:delivered)
        end
      end

      context 'when audit_event_streaming_nats_skip_permanent_failure_redelivery is disabled' do
        let(:error) { URI::InvalidURIError.new }

        before do
          stub_feature_flags(audit_event_streaming_nats_skip_permanent_failure_redelivery: false)
          allow(stream_destination).to receive(:deliver_batch)
            .and_return(outcome_class.new(error: error, error_category: :invalid_config))
        end

        it 'reports a destination error so the batch is redelivered', :aggregate_failures do
          expect(::Gitlab::ErrorTracking).to receive(:log_exception)
            .with(error, hash_including(error_category: :invalid_config, redeliver: true))
          expect(AuditEvents::Streaming::CircuitBreaker).to receive(:record_failure).with(destination)
          expect(::Gitlab::Metrics::AuditEventStreamingSlis).not_to receive(:record_permanent_failure)

          expect(dispatcher.execute).to eq(:destination_error)
        end
      end
    end

    context 'when dispatch fails with an error a retry can fix' do
      where(:error, :error_category) do
        Net::ReadTimeout.new          | :timeout
        Errno::ECONNRESET.new         | :connection
        StandardError.new('HTTP 503') | :server_error
        StandardError.new('HTTP 429') | :rate_limited
      end

      with_them do
        before do
          allow(stream_destination).to receive(:deliver_batch)
            .and_return(outcome_class.new(error: error, error_category: error_category))
        end

        it 'reports a destination error so the batch is redelivered', :aggregate_failures do
          expect(::Gitlab::ErrorTracking).to receive(:log_exception)
            .with(error, hash_including(error_category: error_category, redeliver: true))
          expect(::Gitlab::Metrics::AuditEventStreamingSlis).not_to receive(:record_permanent_failure)

          expect(dispatcher.execute).to eq(:destination_error)
        end
      end
    end

    context 'when dispatch raises a destination-side connection error' do
      before do
        allow(stream_destination).to receive(:deliver_batch)
          .and_return(outcome_class.new(error: Errno::ECONNRESET.new, error_category: :connection))
      end

      it 'reports a destination error, not a GitLab-side failure' do
        expect(::Gitlab::ErrorTracking).to receive(:log_exception)

        expect(dispatcher.execute).to eq(:destination_error)
      end
    end

    context 'when the destination rejects the batch with a 4xx' do
      let(:error) { AuditEvents::Streaming::Destinations::DestinationError.new(403) }

      before do
        allow(stream_destination).to receive(:deliver_batch)
          .and_return(outcome_class.new(error: error, error_category: :auth))
      end

      it 'logs the rejection as a permanent failure and acks the batch' do
        expect(::Gitlab::ErrorTracking).to receive(:log_exception)
          .with(kind_of(AuditEvents::Streaming::Destinations::DestinationError), hash_including(error_category: :auth))

        expect(dispatcher.execute).to eq(:delivered)
      end

      it 'records a circuit breaker failure for the destination' do
        expect(AuditEvents::Streaming::CircuitBreaker).to receive(:record_failure).with(destination)
        expect(AuditEvents::Streaming::CircuitBreaker).not_to receive(:record_success)

        dispatcher.execute
      end

      context 'when audit_event_streaming_nats_skip_permanent_failure_redelivery is disabled' do
        before do
          stub_feature_flags(audit_event_streaming_nats_skip_permanent_failure_redelivery: false)
        end

        it 'reports a destination error so the batch is redelivered, not a GitLab-side failure' do
          expect(dispatcher.execute).to eq(:destination_error)
        end
      end
    end

    context 'when building the stream destination raises before delivery' do
      before do
        allow(AuditEvents::Streaming::Destinations::HttpStreamDestination)
          .to receive(:for_batch).and_raise(StandardError, 'boom')
      end

      it 'tracks it as an internal error to redeliver, without an event count, and reports it as failed' do
        expect(::Gitlab::ErrorTracking).to receive(:track_exception) do |error, context|
          expect(error).to be_a(StandardError)
          expect(context).to include(error_category: :internal_error, redeliver: true)
          expect(context).not_to have_key(:event_count)
        end

        expect(dispatcher.execute).to eq(:failed)
      end
    end

    context 'when dispatch raises a GitLab-side error' do
      before do
        allow(stream_destination).to receive(:deliver_batch)
          .and_return(outcome_class.new(error: StandardError.new('bug'), error_category: :internal_error))
      end

      it 'tracks the exception, marks it for redelivery, and reports the delivery as failed' do
        expect(::Gitlab::ErrorTracking).to receive(:track_exception)
          .with(kind_of(StandardError),
            hash_including(error_category: :internal_error, redeliver: true, event_count: 1))

        expect(dispatcher.execute).to eq(:failed)
      end
    end
  end

  context 'with a raising payload' do
    let_it_be(:destination) do
      create(:audit_events_group_external_streaming_destination, :http, group: group)
    end

    let(:other_audit_event) { create(:audit_events_group_audit_event, group_id: group.id) }
    let(:other_payload) { payload.merge('id' => other_audit_event.id.to_s) }

    subject(:dispatcher) { described_class.new(group.id, [payload, other_payload]) }

    before do
      allow(AuditEvents::Streaming::Destinations::HttpStreamDestination)
        .to receive(:for_batch).with(destination).and_return(stream_destination)

      allow(AuditEvents::Group::ExternalStreamingDestination)
        .to receive(:new).and_wrap_original do |method, *args|
          method.call(*args).tap do |dest|
            allow(dest).to receive(:allowed_to_stream?).and_return(true)
          end
        end
    end

    it 'tracks the offending event and still dispatches the valid ones for that destination' do
      allow(dispatcher).to receive(:reconstructed_event).and_call_original
      allow(dispatcher).to receive(:reconstructed_event)
        .with(hash_including('id' => payload['id'])).and_raise(StandardError, 'boom')

      expect(::Gitlab::ErrorTracking).to receive(:track_exception)
        .with(kind_of(StandardError), hash_including(event_id: payload['id']))
      expect(stream_destination).to receive(:deliver_batch) do |bodies|
        expect(bodies.map { |b| b['id'] }).to contain_exactly(other_payload['id'])
        delivered
      end

      dispatcher.execute
    end
  end

  context 'with an active instance destination and no group destination' do
    let_it_be(:instance_destination) do
      create(:audit_events_instance_external_streaming_destination, :http)
    end

    before do
      allow(AuditEvents::Streaming::Destinations::HttpStreamDestination)
        .to receive(:for_batch).with(instance_destination).and_return(stream_destination)
    end

    it 'dispatches the batch to the instance destination' do
      expect(stream_destination).to receive(:deliver_batch) do |bodies|
        expect(bodies.size).to eq(1)
        expect(bodies.first).to include('id' => audit_event.id.to_s, 'event_type' => event_name)
        delivered
      end
      expect(AuditEvents::Streaming::CircuitBreaker).to receive(:record_success).with(instance_destination)

      dispatcher.execute
    end

    context 'when instance-level external audit events are not licensed' do
      before do
        stub_licensed_features(external_audit_events: false)
      end

      it 'does not dispatch' do
        expect(AuditEvents::Streaming::Destinations::HttpStreamDestination).not_to receive(:for_batch)

        dispatcher.execute
      end
    end
  end

  context 'with both a group and an instance destination for the same batch' do
    let_it_be(:group_destination) do
      create(:audit_events_group_external_streaming_destination, :http, group: group)
    end

    let_it_be(:instance_destination) do
      create(:audit_events_instance_external_streaming_destination, :http)
    end

    let(:group_stream_destination) { instance_double(AuditEvents::Streaming::Destinations::HttpStreamDestination) }
    let(:instance_stream_destination) { instance_double(AuditEvents::Streaming::Destinations::HttpStreamDestination) }

    before do
      allow(AuditEvents::Streaming::CircuitBreaker).to receive(:reject_open) { |destinations| destinations }
      allow(AuditEvents::Streaming::Destinations::HttpStreamDestination)
        .to receive(:for_batch).with(group_destination).and_return(group_stream_destination)
      allow(AuditEvents::Streaming::Destinations::HttpStreamDestination)
        .to receive(:for_batch).with(instance_destination).and_return(instance_stream_destination)
    end

    it 'dispatches the batch to both destinations and reports success' do
      expect(group_stream_destination).to receive(:deliver_batch).and_return(delivered)
      expect(instance_stream_destination).to receive(:deliver_batch).and_return(delivered)

      expect(dispatcher.execute).to eq(:delivered)
    end

    it 'attempts every destination and reports failure when one delivery fails' do
      # Instance destination is down; the group one still gets its batch.
      expect(group_stream_destination).to receive(:deliver_batch).and_return(delivered)
      expect(instance_stream_destination).to receive(:deliver_batch)
        .and_return(outcome_class.new(error: StandardError.new('destination down'), error_category: :internal_error))

      expect(dispatcher.execute).to eq(:failed)
    end

    it 'reports the batch as delivered when both destinations fail permanently, counting each once' do
      allow(group_stream_destination).to receive(:deliver_batch)
        .and_return(outcome_class.new(error: URI::InvalidURIError.new, error_category: :invalid_config))
      allow(instance_stream_destination).to receive(:deliver_batch)
        .and_return(outcome_class.new(error: StandardError.new('HTTP 403'), error_category: :auth))

      expect(::Gitlab::Metrics::AuditEventStreamingSlis).to receive(:record_permanent_failure).twice

      expect(dispatcher.execute).to eq(:delivered)
    end

    context 'when one destination fails permanently' do
      let(:auth_error) { Signet::AuthorizationError.new('invalid_grant') }

      before do
        allow(instance_stream_destination).to receive(:deliver_batch)
          .and_return(outcome_class.new(error: auth_error, error_category: :auth))
      end

      it 'reports the batch as delivered and counts the dropped events once', :aggregate_failures do
        expect(group_stream_destination).to receive(:deliver_batch).and_return(delivered)
        expect(::Gitlab::ErrorTracking).to receive(:log_exception)
          .with(auth_error, hash_including(error_category: :auth, redeliver: false, event_count: 1))
        expect(AuditEvents::Streaming::CircuitBreaker).to receive(:record_failure).with(instance_destination)
        expect(::Gitlab::Metrics::AuditEventStreamingSlis).to receive(:record_permanent_failure)
          .with(destination_category: 'http', error_category: :auth, event_count: 1).once

        expect(dispatcher.execute).to eq(:delivered)
      end

      context 'when the other destination fails with an error a retry can fix' do
        let(:timeout_error) { Net::ReadTimeout.new }

        before do
          allow(group_stream_destination).to receive(:deliver_batch)
            .and_return(outcome_class.new(error: timeout_error, error_category: :timeout))
        end

        it 'redelivers, logs both as redelivered, and does not count the events as dropped', :aggregate_failures do
          expect(::Gitlab::ErrorTracking).to receive(:log_exception)
            .with(auth_error, hash_including(error_category: :auth, redeliver: true, event_count: 1))
          expect(::Gitlab::ErrorTracking).to receive(:log_exception)
            .with(timeout_error, hash_including(error_category: :timeout, redeliver: true))
          expect(AuditEvents::Streaming::CircuitBreaker).to receive(:record_failure).twice
          expect(::Gitlab::Metrics::AuditEventStreamingSlis).not_to receive(:record_permanent_failure)

          expect(dispatcher.execute).to eq(:destination_error)
        end
      end

      context 'when the other destination fails on the GitLab side' do
        before do
          allow(group_stream_destination).to receive(:deliver_batch)
            .and_return(outcome_class.new(error: StandardError.new('bug'), error_category: :internal_error))
        end

        it 'reports failure and does not count the events as dropped', :aggregate_failures do
          expect(::Gitlab::ErrorTracking).to receive(:log_exception)
            .with(auth_error, hash_including(redeliver: true))
          expect(::Gitlab::Metrics::AuditEventStreamingSlis).not_to receive(:record_permanent_failure)

          expect(dispatcher.execute).to eq(:failed)
        end
      end
    end

    it 'reports failure (not destination error) when a GitLab-side and a destination error mix' do
      allow(group_stream_destination).to receive(:deliver_batch)
        .and_return(outcome_class.new(error: Errno::ECONNRESET.new, error_category: :connection))
      allow(instance_stream_destination).to receive(:deliver_batch)
        .and_return(outcome_class.new(error: StandardError.new('bug'), error_category: :internal_error))

      expect(dispatcher.execute).to eq(:failed)
    end
  end

  context 'with no destinations' do
    it 'does nothing and reports success (nothing to deliver)' do
      expect(AuditEvents::Streaming::Destinations::HttpStreamDestination).not_to receive(:for_batch)

      expect(dispatcher.execute).to eq(:delivered)
    end
  end
end
