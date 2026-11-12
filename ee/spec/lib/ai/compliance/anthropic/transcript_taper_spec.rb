# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Ai::Compliance::Anthropic::TranscriptTaper, feature_category: :ai_governance do
  let(:now) { Time.utc(2026, 7, 2, 12) }

  def walk_state(message_watermark: 'clsm_1', walk_started_at: nil, finished_ago: 0, created_at: now - 2.days)
    build(:ai_compliance_anthropic_session,
      message_watermark: message_watermark, walk_started_at: walk_started_at, updated_at: now - finished_ago,
      created_at: created_at)
  end

  def due?(state, last_message_at)
    described_class.due?(walk_state: state, last_message_at: last_message_at, now: now)
  end

  it 'is due when no walk-state row exists' do
    expect(due?(nil, now)).to be(true)
  end

  it 'is due when the row exists but no walk has finished yet' do
    state = walk_state(message_watermark: nil, finished_ago: 1.hour, created_at: now - 1.hour)

    expect(due?(state, now - 1.day)).to be(true)
  end

  it 'is due for a freshly created row' do
    expect(described_class.due?(walk_state: create(:ai_compliance_anthropic_session), last_message_at: 1.day.ago))
      .to be(true)
  end

  it 'backs off after a walk that finished without a watermark' do
    expect(due?(walk_state(message_watermark: nil, finished_ago: 1.hour), now - 1.day)).to be(false)
  end

  it 'is not due while a walk is in progress' do
    expect(due?(walk_state(walk_started_at: now - 1.hour), now - 1.minute)).to be(false)
  end

  it 'is not due while the first walk is in progress, even if updated_at has not moved' do
    state = walk_state(message_watermark: nil, walk_started_at: now - 1.hour, finished_ago: 2.days)

    expect(due?(state, now - 1.minute)).to be(false)
  end

  it 'is due when the previous walk is stale' do
    expect(due?(walk_state(walk_started_at: now - described_class::STALE_WALK_AFTER), now - 1.day)).to be(true)
  end

  it 'retries a failed walk at the next 6-hourly session listing' do
    expect(due?(walk_state(walk_started_at: now - 6.hours), now - 6.hours)).to be(true)
  end

  it 'is due when the last message time is unknown' do
    expect(due?(walk_state, nil)).to be(true)
  end

  it 'accepts the last message time as an RFC 3339 string' do
    expect(due?(walk_state(finished_ago: 30.minutes), '2026-07-02T08:00:00Z')).to be(false)
  end

  it 'treats a malformed last message time like an unknown one' do
    state = walk_state(finished_ago: 30.minutes)

    expect(due?(state, 'not-a-time')).to eq(due?(state, nil))
  end

  where(:quiet_for, :finished_ago, :due) do
    [
      [10.minutes, 1.minute, true],
      [2.hours, 59.minutes, false],
      [2.hours, 1.hour, true],
      [8.hours, 2.hours, false],
      [8.hours, 3.hours, true],
      [3.days, 5.hours, false],
      [3.days, 6.hours, true]
    ]
  end

  with_them do
    it 'backs off as the session goes quiet, whatever its age' do
      expect(due?(walk_state(finished_ago: finished_ago), now - quiet_for)).to be(due)
    end
  end
end
