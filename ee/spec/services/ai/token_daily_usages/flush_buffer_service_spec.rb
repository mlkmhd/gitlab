# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Ai::TokenDailyUsages::FlushBufferService, :clean_gitlab_redis_shared_state,
  feature_category: :ai_abstraction_layer do
  let_it_be(:organization) { create(:organization) }
  let_it_be(:user) { create(:user) }
  let_it_be(:group) { create(:group, organization: organization) }

  let(:timestamp) { Time.current.utc.beginning_of_day + 12.hours }

  def execute
    described_class.new.execute
  end

  def add_to_buffer(at: timestamp, **overrides)
    Ai::TokenDailyUsage.write_buffer.add({
      organization_id: organization.id,
      traversal_ids: group.traversal_ids,
      user_id: user.id,
      feature: 'chat',
      model: 'claude-sonnet-4-5',
      usage_date: at.utc.to_date,
      input_tokens: 100,
      output_tokens: 20,
      events_count: 1,
      namespace_id: group.id,
      event: 'report_duo_chat_token_usage',
      timestamp: at
    }.merge(overrides))
  end

  def daily_rows
    Ai::TokenDailyUsage.order(:usage_date, :model).map do |row|
      row.slice(:usage_date, :model, :input_tokens, :output_tokens, :events_count).symbolize_keys
    end
  end

  it 'writes nothing when the buffer is empty' do
    expect(execute.payload).to eq({ inserted_rows: 0, dropped_rows: 0 })
    expect(Ai::TokenDailyUsage.count).to eq(0)
  end

  it 'sums the events of one day key into one row with a single upsert' do
    add_to_buffer
    add_to_buffer(at: timestamp + 1.minute, input_tokens: 50, output_tokens: 5)

    expect(Ai::TokenDailyUsage).to receive(:upsert_all).once.and_call_original
    expect(execute.payload).to eq({ inserted_rows: 1, dropped_rows: 0 })
    expect(daily_rows).to eq([
      { usage_date: timestamp.to_date, model: 'claude-sonnet-4-5', input_tokens: 150, output_tokens: 25,
        events_count: 2 }
    ])
  end

  it 'writes a row under the organization its namespace has when the buffer is flushed' do
    moved_group = create(:group, organization: organization)
    new_organization = create(:organization)
    add_to_buffer(traversal_ids: moved_group.traversal_ids, namespace_id: moved_group.id)
    moved_group.update_column(:organization_id, new_organization.id)

    execute

    expect(Ai::TokenDailyUsage.pluck(:organization_id)).to contain_exactly(new_organization.id)
  end

  it 'keeps the buffered organization when the namespace no longer exists' do
    add_to_buffer(traversal_ids: [non_existing_record_id], namespace_id: non_existing_record_id)

    expect(execute.payload).to eq({ inserted_rows: 1, dropped_rows: 0 })
    expect(Ai::TokenDailyUsage.pluck(:organization_id)).to contain_exactly(organization.id)
  end

  it 'writes a row with no namespace under the organization its user has when the buffer is flushed' do
    moved_user = create(:user)
    new_organization = create(:organization)
    add_to_buffer(traversal_ids: [], namespace_id: nil, user_id: moved_user.id)
    moved_user.update_column(:organization_id, new_organization.id)

    execute

    expect(Ai::TokenDailyUsage.pluck(:organization_id)).to contain_exactly(new_organization.id)
  end

  it 'keeps the buffered organization when the user of a row with no namespace no longer exists' do
    add_to_buffer(traversal_ids: [], namespace_id: nil, user_id: non_existing_record_id)

    expect(execute.payload).to eq({ inserted_rows: 1, dropped_rows: 0 })
    expect(Ai::TokenDailyUsage.pluck(:organization_id)).to contain_exactly(organization.id)
  end

  it 'reads the organizations of the namespaces and of the users in one query each' do
    add_to_buffer
    add_to_buffer(model: 'claude-haiku-4-5')
    add_to_buffer(traversal_ids: [], namespace_id: nil)
    add_to_buffer(traversal_ids: [], namespace_id: nil, user_id: create(:user).id)

    recorder = ActiveRecord::QueryRecorder.new { execute }

    expect(recorder.log.grep(/FROM "namespaces"/).size).to eq(1)
    expect(recorder.log.grep(/FROM "namespaces"/).first).to include(%("namespaces"."id" = #{group.id}))
    expect(recorder.log.grep(/FROM "users"/).size).to eq(1)
  end

  it 'does not read users when every row has a namespace' do
    add_to_buffer

    recorder = ActiveRecord::QueryRecorder.new { execute }

    expect(recorder.log.grep(/FROM "users"/)).to be_empty
  end

  it 'keeps a row per model' do
    add_to_buffer
    add_to_buffer(model: 'claude-haiku-4-5', input_tokens: 7, output_tokens: 3)

    expect(execute.payload).to eq({ inserted_rows: 2, dropped_rows: 0 })
    expect(daily_rows).to contain_exactly(
      hash_including(model: 'claude-sonnet-4-5', input_tokens: 100, output_tokens: 20, events_count: 1),
      hash_including(model: 'claude-haiku-4-5', input_tokens: 7, output_tokens: 3, events_count: 1)
    )
  end

  it 'keeps a row per UTC day across midnight' do
    midnight = Time.current.utc.beginning_of_day

    add_to_buffer(at: midnight - 1.second)
    add_to_buffer(at: midnight)

    execute

    expect(daily_rows.pluck(:usage_date)).to match_array([midnight.to_date - 1.day, midnight.to_date])
  end

  it 'adds a later flush to the row an earlier flush wrote' do
    add_to_buffer
    execute
    stale_updated_at = 1.day.ago
    Ai::TokenDailyUsage.update_all(updated_at: stale_updated_at)
    add_to_buffer(at: timestamp + 1.minute, input_tokens: 50, output_tokens: 5)
    execute

    expect(daily_rows).to eq([
      { usage_date: timestamp.to_date, model: 'claude-sonnet-4-5', input_tokens: 150, output_tokens: 25,
        events_count: 2 }
    ])
    expect(Ai::TokenDailyUsage.pick(:updated_at)).to be > stale_updated_at
  end

  it 'counts an event once when the buffer holds it twice' do
    add_to_buffer
    add_to_buffer

    expect(execute.payload).to eq({ inserted_rows: 1, dropped_rows: 0 })
    expect(daily_rows).to match_array([hash_including(input_tokens: 100, output_tokens: 20, events_count: 1)])
  end

  it 'drops rows the model rejects and writes the rest' do
    add_to_buffer(input_tokens: -1)
    add_to_buffer(model: 'claude-haiku-4-5', output_tokens: nil)
    add_to_buffer(at: (Ai::TokenDailyUsage::DEFAULT_RETENTION_DAYS + 1).days.ago)
    add_to_buffer(model: 'claude-opus-4-1')

    expect(execute.payload).to eq({ inserted_rows: 1, dropped_rows: 3 })
    expect(daily_rows).to match_array([hash_including(model: 'claude-opus-4-1', events_count: 1)])
  end

  it 'counts a rejected event once when the buffer holds it twice' do
    add_to_buffer(input_tokens: -1)
    add_to_buffer(input_tokens: -1)
    add_to_buffer(model: 'claude-opus-4-1')

    expect(execute.payload).to eq({ inserted_rows: 1, dropped_rows: 1 })
  end

  it 'reports the dropped rows without an upsert when the model rejects every row' do
    add_to_buffer(input_tokens: -1)
    add_to_buffer(model: 'claude-haiku-4-5', output_tokens: nil)

    expect(Ai::TokenDailyUsage).not_to receive(:upsert_all)
    expect(execute.payload).to eq({ inserted_rows: 0, dropped_rows: 2 })
    expect(Ai::TokenDailyUsage.count).to eq(0)
  end

  context 'when the upsert fails' do
    before do
      add_to_buffer
    end

    it 'puts the batch back and raises' do
      allow(Ai::TokenDailyUsage).to receive(:upsert_all).and_raise(ActiveRecord::QueryCanceled)

      expect { execute }.to raise_error(ActiveRecord::QueryCanceled)
      expect(Ai::TokenDailyUsage.write_buffer.pop(10).size).to eq(1)
    end

    it 'keeps the batch when the buffer refilled to the cap while it was out' do
      stub_feature_flags(analytics_write_buffer_protection: true)
      stub_const('Analytics::DatabaseWriteBuffer::MAX_PENDING', 1)
      allow(Ai::TokenDailyUsage).to receive(:upsert_all) do
        add_to_buffer(model: 'claude-haiku-4-5')
        raise ActiveRecord::QueryCanceled
      end

      expect { execute }.to raise_error(ActiveRecord::QueryCanceled)
      expect(Ai::TokenDailyUsage.write_buffer.pending).to eq(2)
    end

    it 'adds the batch once on the next run' do
      allow(Ai::TokenDailyUsage).to receive(:upsert_all).and_raise(ActiveRecord::QueryCanceled)
      expect { execute }.to raise_error(ActiveRecord::QueryCanceled)

      allow(Ai::TokenDailyUsage).to receive(:upsert_all).and_call_original
      execute

      expect(daily_rows).to match_array([hash_including(input_tokens: 100, output_tokens: 20, events_count: 1)])
    end
  end

  context 'when the pop fails' do
    it 'raises the pop error and does not add a batch back' do
      allow(Ai::TokenDailyUsage.write_buffer).to receive(:pop).and_raise(Redis::CannotConnectError)

      expect(Ai::TokenDailyUsage.write_buffer).not_to receive(:requeue)
      expect { execute }.to raise_error(Redis::CannotConnectError)
    end
  end
end
