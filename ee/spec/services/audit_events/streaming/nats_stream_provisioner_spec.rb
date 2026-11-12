# frozen_string_literal: true

require 'spec_helper'

RSpec.describe AuditEvents::Streaming::NatsStreamProvisioner, feature_category: :audit_events do
  include ExclusiveLeaseHelpers

  let(:client) { instance_double(Gitlab::Nats::Client) }

  before do
    allow(::Gitlab::Nats).to receive(:client).and_return(client)
    allow(client).to receive_messages(consumer_info: nil, add_consumer: nil)
  end

  describe '#ensure!' do
    context 'when the stream does not exist' do
      before do
        allow(client).to receive(:stream_info).with(described_class::STREAM_NAME).and_return(nil)
      end

      it 'creates the stream' do
        expect(client).to receive(:add_stream).with(hash_including(name: described_class::STREAM_NAME))

        expect(described_class.new.ensure!.action).to eq(:created)
      end
    end

    context 'when the stream exists and matches' do
      let(:config) do
        double('StreamConfig', # rubocop:disable RSpec/VerifiedDoubles -- nats-pure API object
          subjects: [described_class::SUBJECT_FILTER],
          num_replicas: described_class::DEFAULT_NUM_REPLICAS,
          max_age: described_class::MAX_AGE.to_i * 1_000_000_000,
          duplicate_window: described_class::DUPLICATE_WINDOW.to_i * 1_000_000_000
        )
      end

      let(:info) { double('StreamInfo', config: config) } # rubocop:disable RSpec/VerifiedDoubles -- nats-pure API object

      before do
        allow(client).to receive(:stream_info).with(described_class::STREAM_NAME).and_return(info)
      end

      it 'is a no-op' do
        expect(client).not_to receive(:add_stream)
        expect(client).not_to receive(:update_stream)

        expect(described_class.new.ensure!.action).to eq(:exists)
      end
    end

    context 'when the stream exists but drifts' do
      let(:config) do
        double('StreamConfig', # rubocop:disable RSpec/VerifiedDoubles -- nats-pure API object
          subjects: ['audit_events.streaming.old'],
          num_replicas: 1,
          max_age: 0,
          duplicate_window: 0
        )
      end

      let(:info) { double('StreamInfo', config: config) } # rubocop:disable RSpec/VerifiedDoubles -- nats-pure API object

      before do
        allow(client).to receive(:stream_info).with(described_class::STREAM_NAME).and_return(info)
      end

      it 'updates the stream' do
        expect(client).to receive(:update_stream).with(hash_including(name: described_class::STREAM_NAME))

        expect(described_class.new.ensure!.action).to eq(:updated)
      end
    end

    describe 'durable consumers' do
      let(:durables) { %w[audit_streaming_consumer_0 audit_streaming_consumer_instance] }
      let(:jetstream_defaults) { { ack_wait: 30, max_deliver: -1, backoff: nil } }
      let(:redelivery_config) do
        described_class.new.desired_consumer_config(0).slice(:ack_wait, :max_deliver, :backoff)
      end

      def stub_consumers(config)
        info = config && double('ConsumerInfo', config: double('ConsumerConfig', config)) # rubocop:disable RSpec/VerifiedDoubles -- nats-pure API objects

        durables.each do |durable|
          allow(client).to receive(:consumer_info).with(described_class::STREAM_NAME, durable).and_return(info)
        end
      end

      before do
        allow(client).to receive_messages(stream_info: nil, add_stream: nil)
      end

      it 'creates a missing consumer for every partition key' do
        stub_consumers(nil)

        durables.each do |durable|
          expect(client).to receive(:add_consumer)
            .with(described_class::STREAM_NAME, hash_including(durable_name: durable, **redelivery_config))
        end

        described_class.new.ensure!
      end

      it 'updates consumers still on the JetStream defaults in place' do
        stub_consumers(jetstream_defaults)

        expect(client).to receive(:add_consumer)
          .with(described_class::STREAM_NAME, hash_including(redelivery_config)).twice

        described_class.new.ensure!
      end

      it 'leaves consumers that already match alone' do
        stub_consumers(redelivery_config)

        expect(client).not_to receive(:add_consumer)

        described_class.new.ensure!
      end

      context 'when audit_event_streaming_nats_consumer_redelivery is disabled' do
        before do
          stub_feature_flags(audit_event_streaming_nats_consumer_redelivery: false)
        end

        it 'restores the JetStream defaults on consumers that have the redelivery config' do
          stub_consumers(ack_wait: 120, max_deliver: 10, backoff: [120_000_000_000])

          expect(client).to receive(:add_consumer)
            .with(described_class::STREAM_NAME, hash_including(ack_wait: 30, max_deliver: -1)).twice

          described_class.new.ensure!
        end

        it 'leaves consumers on the JetStream defaults alone' do
          stub_consumers(jetstream_defaults)

          expect(client).not_to receive(:add_consumer)

          described_class.new.ensure!
        end
      end
    end
  end

  describe '.ensure_once!' do
    it 'runs ensure! when the lease can be obtained' do
      stub_exclusive_lease(described_class::ENSURE_LEASE_KEY, 'lease-uuid')
      allow(client).to receive(:stream_info).and_return(nil)
      allow(client).to receive(:add_stream)

      expect(described_class.ensure_once!).to be_a(described_class::Result)
    end

    it 'is a no-op when the lease is already held' do
      stub_exclusive_lease_taken(described_class::ENSURE_LEASE_KEY)

      expect(client).not_to receive(:stream_info)

      expect(described_class.ensure_once!).to be_nil
    end

    it 'cancels the lease and re-raises when ensure! fails, so the next tick retries' do
      lease_uuid = 'lease-uuid'
      stub_exclusive_lease(described_class::ENSURE_LEASE_KEY, lease_uuid)
      allow(client).to receive(:stream_info).and_return(nil)
      allow(client).to receive(:add_stream).and_raise(StandardError, 'nats down')

      expect_to_cancel_exclusive_lease(described_class::ENSURE_LEASE_KEY, lease_uuid)

      expect { described_class.ensure_once! }.to raise_error(StandardError, 'nats down')
    end
  end

  describe '#desired_consumer_config' do
    it 'acks within 2 minutes and backs off up to 10 deliveries', :aggregate_failures do
      config = described_class.new.desired_consumer_config(0)

      expect(config).to include(
        durable_name: 'audit_streaming_consumer_0',
        filter_subject: 'audit_events.streaming.0',
        ack_policy: 'explicit',
        ack_wait: 120,
        max_deliver: 10
      )
      expect(config[:backoff]).to eq([120, 300, 900, 1800, 3600].map { |seconds| seconds * 1_000_000_000 })
      expect(config[:max_deliver]).to be > config[:backoff].size
    end

    it 'targets the instance lane for the instance key' do
      expect(described_class.new.desired_consumer_config('instance')).to include(
        durable_name: 'audit_streaming_consumer_instance',
        filter_subject: 'audit_events.streaming.instance'
      )
    end

    context 'when audit_event_streaming_nats_consumer_redelivery is disabled' do
      before do
        stub_feature_flags(audit_event_streaming_nats_consumer_redelivery: false)
      end

      it 'uses the JetStream defaults', :aggregate_failures do
        config = described_class.new.desired_consumer_config(0)

        expect(config).to include(ack_wait: 30, max_deliver: -1)
        expect(config).not_to have_key(:backoff)
      end
    end
  end

  describe '#desired_config' do
    subject(:config) { described_class.new.desired_config }

    it 'sets limits retention, file storage, replication, and 24h max_age' do
      expect(config).to include(
        name: described_class::STREAM_NAME,
        subjects: [described_class::SUBJECT_FILTER],
        retention: :limits,
        storage: :file,
        num_replicas: described_class::DEFAULT_NUM_REPLICAS
      )
      expect(config[:max_age]).to eq(24.hours.to_i * 1_000_000_000)
      expect(config[:duplicate_window]).to eq(described_class::DUPLICATE_WINDOW.to_i * 1_000_000_000)
    end

    it 'uses the configured stream_replicas (e.g. 3 for clustered production)' do
      allow(::Settings.nats).to receive(:stream_replicas).and_return(3)

      expect(described_class.new.desired_config[:num_replicas]).to eq(3)
    end
  end
end
