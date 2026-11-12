# frozen_string_literal: true

require 'spec_helper'

RSpec.describe UsageEvents::DumpWriteBufferCronWorker, :clean_gitlab_redis_shared_state, feature_category: :value_stream_management do
  let_it_be(:organization) { create(:organization) }
  let(:job) { described_class.new }
  let(:perform) { job.perform }
  let_it_be(:personal_namespace) { create(:user_namespace) }

  let(:inserted_records) do
    Ai::UsageEvent.all.map(&:attributes)
  end

  it 'does not insert anything' do
    perform

    expect(inserted_records).to be_empty
  end

  def add_to_buffer(attributes)
    data = { 'timestamp' => Time.current }.merge(attributes.stringify_keys)
    data['event'] = Ai::UsageEvent.events[data['event']] if data['event'].is_a?(String)
    Ai::UsageEvent.write_buffer.add(data)
  end

  context 'when data is present' do
    before do
      add_to_buffer(user_id: 3, event: 'request_duo_chat_response', organization_id: organization.id)
      add_to_buffer(user_id: 1, event: 'code_suggestion_shown_in_ide', organization_id: organization.id)

      timestamp = Time.current
      add_to_buffer(
        user_id: 2,
        event: 'code_suggestion_shown_in_ide',
        organization_id: organization.id,
        timestamp: timestamp
      )
      add_to_buffer(
        user_id: 2,
        event: 'code_suggestion_shown_in_ide',
        organization_id: organization.id,
        timestamp: timestamp
      )
      # Already existing record for Ai::UsageEvent
      Ai::UsageEvent.create!(
        user_id: 2,
        event: 'code_suggestion_shown_in_ide',
        organization_id: organization.id,
        timestamp: timestamp
      )

      add_to_buffer(user_id: 3,
        event: 'troubleshoot_job',
        organization_id: organization.id,
        namespace_id: personal_namespace.id,
        extras: { foo: 'bar' })
    end

    it 'inserts all rows' do
      status = perform

      expect(status).to eq({ status: :processed, inserted_rows: 4 })
      expect(inserted_records).to match([
        hash_including('user_id' => 3, 'event' => 'request_duo_chat_response'),
        hash_including('user_id' => 1, 'event' => 'code_suggestion_shown_in_ide'),
        hash_including('user_id' => 2, 'event' => 'code_suggestion_shown_in_ide'),
        hash_including('user_id' => 3, 'event' => 'troubleshoot_job')
      ])
    end

    it 'deduplicates identical events' do
      status = perform

      expect(status).to eq({ status: :processed, inserted_rows: 4 })

      expect(Ai::UsageEvent.where(user_id: 2).count).to eq(1)
    end

    context 'when looping twice' do
      it 'inserts all rows' do
        stub_const("#{described_class.name}::BATCH_SIZE", 2)

        expect(perform).to eq({ status: :processed, inserted_rows: 4 })
      end
    end

    context 'when time limit is up' do
      it 'returns over_time status' do
        stub_const("#{described_class.name}::BATCH_SIZE", 1)

        allow_next_instance_of(Gitlab::Metrics::RuntimeLimiter) do |limiter|
          allow(limiter).to receive(:over_time?).and_return(false, false, true)
        end

        status = perform

        expect(status).to eq({ status: :over_time, inserted_rows: 3 })
        expect(inserted_records).to match([
          hash_including('user_id' => 3),
          hash_including('user_id' => 1),
          hash_including('user_id' => 2) # already exist in the database
        ])
      end
    end
  end

  context 'when data contains different sets of attributes' do
    before do
      add_to_buffer(user_id: 1,
        event: 'request_duo_chat_response',
        organization_id: organization.id)
      add_to_buffer(user_id: 2,
        event: 'request_duo_chat_response',
        organization_id: organization.id)
      add_to_buffer(user_id: 3,
        event: 'request_duo_chat_response',
        organization_id: organization.id,
        namespace_id: personal_namespace.id)
    end

    it 'inserts all rows by attribute groups' do
      expect(Ai::UsageEvent).to receive(:upsert_all).twice.and_call_original
      expect(perform).to eq({ status: :processed, inserted_rows: 3 })
    end
  end

  context 'when data contains obsolete attributes' do
    before do
      add_to_buffer(user_id: 1,
        event: 'request_duo_chat_response',
        organization_id: organization.id)
      add_to_buffer(user_id: 2,
        event: 'request_duo_chat_response',
        organization_id: organization.id,
        foo: 'bar')
    end

    it 'ignores extra attributes and inserts all rows' do
      expect(Ai::UsageEvent).to receive(:upsert_all).once.and_call_original
      expect(perform).to eq({ status: :processed, inserted_rows: 2 })
    end
  end

  context 'when data contains multiple duplicates' do
    before do
      timestamp = Time.current
      add_to_buffer(user_id: 1,
        event: 'request_duo_chat_response',
        organization_id: organization.id,
        timestamp: timestamp, extras: { foo: '1' })
      add_to_buffer(user_id: 1,
        event: 'request_duo_chat_response',
        organization_id: organization.id,
        timestamp: timestamp, extras: { foo: '2' })
      add_to_buffer(user_id: 1,
        event: 'request_duo_chat_response',
        organization_id: organization.id,
        timestamp: timestamp, extras: { foo: '3' })
    end

    it 'inserts only 1 row' do
      expect(perform).to eq({ status: :processed, inserted_rows: 1 })
      expect(inserted_records).to match([hash_including('extras' => { 'foo' => '1' })])
    end
  end

  context 'when processing fails with exception' do
    before do
      timestamp = Time.current
      add_to_buffer(user_id: 1,
        event: 'request_duo_chat_response',
        organization_id: organization.id,
        timestamp: timestamp, extras: { foo: '1' })
    end

    it 'pushes back values for reprocessing and reraises' do
      error = StandardError.new
      allow(Ai::UsageEvent).to receive(:upsert_all).and_raise(error)
      expect(Ai::UsageEvent.write_buffer).to receive(:requeue).once.and_call_original
      expect(Ai::UsageEvent.write_buffer).not_to receive(:add)

      expect { perform }.to raise_error(error)

      expect(Ai::UsageEvent.write_buffer.pending).to eq(1)
    end

    context 'when the buffer filled up to the cap while the batch was out' do
      let(:dropped) { instance_double(Prometheus::Client::Counter, increment: nil) }

      before do
        stub_const("#{Analytics::DatabaseWriteBuffer}::MAX_PENDING", 1)
        allow(Gitlab::Metrics).to receive(:counter).and_call_original
        allow(Gitlab::Metrics).to receive(:counter)
          .with(:gitlab_database_write_buffer_dropped_total, anything).and_return(dropped)
      end

      it 'keeps the failed batch past the cap' do
        allow(Ai::UsageEvent).to receive(:upsert_all) do
          add_to_buffer(user_id: 2, event: 'request_duo_chat_response', organization_id: organization.id)
          raise ActiveRecord::StatementInvalid, 'boom'
        end

        expect { perform }.to raise_error(ActiveRecord::StatementInvalid)

        expect(Ai::UsageEvent.write_buffer.pending).to eq(2)
        expect(Ai::UsageEvent.write_buffer.pop(2).pluck('user_id')).to eq([2, 1])
        expect(dropped).not_to have_received(:increment)
      end
    end
  end

  describe 'pending gauge' do
    let(:gauge) { instance_double(Prometheus::Client::Gauge, set: nil) }

    before do
      allow(Gitlab::Metrics).to receive(:gauge).and_call_original
      allow(Gitlab::Metrics).to receive(:gauge)
        .with(:gitlab_database_write_buffer_pending, anything, {}, :max).and_return(gauge)
      add_to_buffer(user_id: 1, event: 'request_duo_chat_response', organization_id: organization.id)
      add_to_buffer(user_id: 2, event: 'request_duo_chat_response', organization_id: organization.id)
    end

    it 'records the buffer length before draining, labelled by table' do
      expect(gauge).to receive(:set).with({ table: 'ai_usage_events' }, 2)
      expect(job).to receive(:log_extra_metadata_on_done).with(:pending_rows, 2)
      expect(job).to receive(:log_extra_metadata_on_done).with(:result, anything)

      perform
    end
  end

  context 'when data contains data before typecast and after typecast' do
    it 'saves both events properly' do
      # event is string
      Ai::UsageEvent.write_buffer.add({
        user_id: 1,
        event: 'request_duo_chat_response',
        organization_id: organization.id,
        timestamp: Time.current
      }.stringify_keys)
      # event is integer
      add_to_buffer(user_id: 2,
        event: 'request_duo_chat_response',
        organization_id: organization.id)

      expect(perform).to eq({ status: :processed, inserted_rows: 2 })
      expect(inserted_records)
        .to match([hash_including('event' => 'request_duo_chat_response'),
          hash_including('event' => 'request_duo_chat_response')])
    end
  end

  # Until idx_ai_usage_events_uniqueness is dropped, it still rejects the same tuple in a
  # second organization, even though the upsert targets the organization-scoped index.
  context 'when the same event already exists in another organization' do
    let_it_be(:other_organization) { create(:organization) }
    let(:timestamp) { Time.current }

    where(:namespace) do
      [
        [ref(:personal_namespace)],
        [nil]
      ]
    end

    with_them do
      before do
        Ai::UsageEvent.create!(user_id: 1, event: 'request_duo_chat_response', organization_id: organization.id,
          namespace_id: namespace&.id, timestamp: timestamp)
        add_to_buffer(user_id: 1, event: 'request_duo_chat_response', organization_id: other_organization.id,
          namespace_id: namespace&.id, timestamp: timestamp)
      end

      it 'is rejected by the old unique index and the batch is kept for retry', :aggregate_failures do
        # A savepoint keeps the spec's transaction usable after the unique violation.
        expect { ApplicationRecord.transaction(requires_new: true) { perform } }
          .to raise_error(ActiveRecord::RecordNotUnique)
        expect(Ai::UsageEvent.where(user_id: 1).pluck(:organization_id)).to eq([organization.id])
        expect(Ai::UsageEvent.write_buffer.pop(10).size).to eq(1)
      end
    end
  end

  context 'when data contains invalid namespace id' do
    it 'filters out events with incorrect namespace_id' do
      add_to_buffer(user_id: 1,
        event: 'request_duo_chat_response',
        organization_id: organization.id,
        namespace_id: non_existing_record_id)
      add_to_buffer(user_id: 2,
        event: 'request_duo_chat_response',
        organization_id: organization.id)

      expect(perform).to eq({ status: :processed, inserted_rows: 1 })
      expect(inserted_records).to match([hash_including('user_id' => 2)])
    end
  end
end
