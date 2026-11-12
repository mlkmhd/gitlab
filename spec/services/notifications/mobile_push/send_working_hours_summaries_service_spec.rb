# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Notifications::MobilePush::SendWorkingHoursSummariesService, :clean_gitlab_redis_shared_state,
  feature_category: :notifications do
  let_it_be(:project) { create(:project) }

  let(:user) { create(:user) }
  let(:client) { instance_double(::Gitlab::MobilePush::ApnsClient, close: nil) }
  # Wednesday 09:00 in Berlin, the start of the schedule below.
  let(:now) { Time.utc(2026, 10, 7, 7, 0) }
  let(:hold) { ::Gitlab::MobilePush::WorkingHoursHold }

  subject(:execute) { travel_to(now) { described_class.new.execute } }

  before do
    allow(::Gitlab::MobilePush::ApnsClient).to receive(:new).and_return(client)
    allow(client).to receive(:push).and_return(:delivered)
  end

  # A due user with a phone and one pending to-do, the common case.
  def hold_with_phone(for_user, resume_at = now)
    for_user.user_preference.update!(
      mobile_push_working_hours_enabled: true,
      mobile_push_working_hours_start: 9 * 60,
      mobile_push_working_hours_end: 17 * 60,
      mobile_push_working_days: %w[monday tuesday wednesday thursday friday],
      mobile_push_working_hours_time_zone: 'Europe/Berlin'
    )
    create(:mobile_device_push_subscription, user: for_user)
    create(:todo, user: for_user, project: project)
    hold.record(for_user.id, resume_at)
  end

  it 'sends the summary to a due user, clears the hold and closes the connection' do
    hold_with_phone(user, now - 1.minute)

    expect(execute.payload).to eq(delivered: 1)
    expect(client).to have_received(:push)
      .with(user.mobile_device_push_subscriptions.first, an_instance_of(::Gitlab::MobilePush::SummaryPayload))
    expect(hold.due_user_ids(now + 7.days, limit: 10)).to be_empty
    expect(client).to have_received(:close)
  end

  it 'tallies the outcomes across users' do
    rescheduled_user = create(:user)
    [user, rescheduled_user].each { |due_user| hold_with_phone(due_user) }
    # One window has closed again since the hold: Wednesday was dropped.
    rescheduled_user.user_preference.update!(mobile_push_working_days: %w[monday tuesday thursday friday])

    expect(execute.payload).to eq(delivered: 1, rescheduled: 1)
  end

  it 'leaves a user whose window has not opened yet alone' do
    hold_with_phone(user, now + 1.hour)

    expect(execute.payload).to eq({})
    expect(client).not_to have_received(:push)
    expect(hold.due_user_ids(now + 1.hour, limit: 10)).to eq([user.id])
  end

  it 'skips a user another run claimed first' do
    hold_with_phone(user)
    allow(hold).to receive(:claim).and_call_original
    allow(hold).to receive(:claim).with(user.id).and_return(false)

    expect(execute.payload).to eq({})
    expect(client).not_to have_received(:push)
  end

  it 'drops a user who no longer exists so they do not fill the batch forever' do
    hold.record(non_existing_record_id, now)

    expect(execute.payload).to eq(skipped_user_missing: 1)
    expect(client).not_to have_received(:push)
    expect(hold.due_user_ids(now, limit: 10)).to be_empty
  end

  it 'sends once across two runs over the same due list' do
    hold_with_phone(user)

    travel_to(now) do
      described_class.new.execute
      described_class.new.execute
    end

    expect(client).to have_received(:push).once
  end

  it 'handles at most BATCH_SIZE users per run and leaves the rest due' do
    stub_const("#{described_class}::BATCH_SIZE", 1)
    [user, create(:user)].each { |due_user| hold_with_phone(due_user) }

    expect(execute.payload).to eq(delivered: 1)
    expect(hold.due_user_ids(now, limit: 10).size).to eq(1)
  end

  it 'stops at the runtime limit, reaching the earliest-due user first' do
    # The newer user has been waiting longer, so they go before the lower id.
    hold_with_phone(user, now - 1.minute)
    earlier_due_user = create(:user)
    hold_with_phone(earlier_due_user, now - 1.hour)
    allow_next_instance_of(::Gitlab::Metrics::RuntimeLimiter) do |limiter|
      allow(limiter).to receive(:over_time?).and_return(false, true)
    end

    expect(execute.payload).to eq(delivered: 1)
    expect(client).to have_received(:push)
      .with(earlier_due_user.mobile_device_push_subscriptions.first, an_instance_of(::Gitlab::MobilePush::SummaryPayload))
    expect(hold.due_user_ids(now, limit: 10)).to eq([user.id])
  end

  it 'loads the due users in a constant number of queries' do
    hold_with_phone(user)

    control = ActiveRecord::QueryRecorder.new { execute }

    ([user] + create_list(:user, 3)).each { |due_user| hold_with_phone(due_user) }

    expect { travel_to(now) { described_class.new.execute } }
      .not_to exceed_query_limit(control)
      .for_query(/FROM "(users|user_preferences|mobile_device_push_subscriptions)"/)
  end
end
