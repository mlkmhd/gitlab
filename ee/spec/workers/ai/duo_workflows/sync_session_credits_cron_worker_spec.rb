# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Ai::DuoWorkflows::SyncSessionCreditsCronWorker, :clean_gitlab_redis_shared_state,
  feature_category: :value_stream_management do
  let_it_be(:root_group) { create(:group) }
  let_it_be(:other_root) { create(:group) }
  let_it_be(:third_root) { create(:group) }
  let_it_be(:fourth_root) { create(:group) }

  let(:child_worker) { Ai::DuoWorkflows::SyncNamespaceSessionCreditsWorker }
  let(:usage_client) { instance_double(Gitlab::SubscriptionPortal::SubscriptionUsageClient) }
  let(:client_error) { Gitlab::SubscriptionPortal::SubscriptionUsageClient::ResponseError }
  let(:worker) { described_class.new }

  subject(:perform) { worker.perform }

  before do
    allow(Gitlab::ClickHouse).to receive(:globally_enabled_for_analytics?).and_return(true)
    allow(Gitlab::Saas).to receive(:feature_available?).and_call_original
    allow(Gitlab::Saas).to receive(:feature_available?).with(:gitlab_com_subscriptions).and_return(true)
    allow(Gitlab::SubscriptionPortal::SubscriptionUsageClient).to receive(:new).and_return(usage_client)
    stub_pages(page)
    allow(child_worker).to receive(:bulk_perform_async_with_contexts)
    allow(child_worker).to receive(:bulk_perform_in_with_contexts)
    allow(child_worker).to receive(:perform_async)
    allow(worker).to receive(:log_extra_metadata_on_done).and_call_original
  end

  def page(*namespaces, end_cursor: nil)
    {
      success: true,
      namespaces: namespaces.map do |namespace|
        id = namespace.is_a?(Group) ? namespace.id : namespace
        { rootNamespaceId: id.to_s, updatedAt: '2026-10-19T10:00:00.000000Z' }
      end,
      page_info: { hasNextPage: end_cursor.present?, endCursor: end_cursor }
    }
  end

  def stub_pages(*pages)
    allow(usage_client).to receive(:get_session_namespaces).and_return(*pages)
  end

  # Captures [delay_seconds, groups] per enqueue call, checking the procs on the way.
  def enqueued_batches
    batches = []
    record = ->(delay, groups, arguments_proc, context_proc) do
      groups.each do |group|
        expect(arguments_proc.call(group)).to eq(group.id)
        expect(context_proc.call(group)).to eq(namespace: group)
      end

      batches << [delay.to_i, groups]
    end

    allow(child_worker).to receive(:bulk_perform_async_with_contexts) do |groups, arguments_proc:, context_proc:|
      record.call(0, groups, arguments_proc, context_proc)
    end
    allow(child_worker).to receive(:bulk_perform_in_with_contexts) do |delay, groups, arguments_proc:, context_proc:|
      record.call(delay, groups, arguments_proc, context_proc)
    end

    batches
  end

  def enqueued_groups
    batches = enqueued_batches

    Class.new do
      define_method(:to_a) { batches.flat_map(&:last) }
      define_method(:empty?) { to_a.empty? }
    end.new
  end

  def expect_logged(key, value)
    expect(worker).to have_received(:log_extra_metadata_on_done).with(key, value)
  end

  def expect_nothing_enqueued
    expect(child_worker).not_to have_received(:bulk_perform_async_with_contexts)
    expect(child_worker).not_to have_received(:bulk_perform_in_with_contexts)
  end

  it_behaves_like 'an idempotent worker' do
    before do
      stub_pages(page(root_group))
    end
  end

  it 'enqueues one job per root namespace that CustomersDot billed in the activity window', :aggregate_failures do
    stub_pages(page(root_group, other_root))
    enqueued = enqueued_groups

    perform

    expect(enqueued).to contain_exactly(root_group, other_root)
    expect_logged(:namespaces_enumerated, 2)
    expect_logged(:namespaces_enqueued, 2)
    expect_logged(:stop_reason, :completed)
  end

  it 'asks for the activity window and walks every page', :aggregate_failures, :freeze_time do
    expect(usage_client).to receive(:get_session_namespaces)
      .with(updated_after: 90.days.ago, after: nil).and_return(page(root_group, end_cursor: 'next'))
    expect(usage_client).to receive(:get_session_namespaces)
      .with(updated_after: 90.days.ago, after: 'next').and_return(page(other_root))
    enqueued = enqueued_groups

    perform

    expect(enqueued).to contain_exactly(root_group, other_root)
  end

  context 'when the lookup runs over the runtime limit' do
    let(:counter) { instance_double(Prometheus::Client::Counter, increment: nil) }

    before do
      limiter = instance_double(Gitlab::Metrics::RuntimeLimiter, over_time?: true)
      allow(Gitlab::Metrics::RuntimeLimiter).to receive(:new)
        .with(described_class::LOOKUP_MAX_RUNTIME).and_return(limiter)
      allow(Gitlab::Metrics).to receive(:counter).and_call_original
      allow(Gitlab::Metrics).to receive(:counter)
        .with(:duo_workflow_session_credits_v2_fetch_failures_total, anything).and_return(counter)
    end

    it 'enqueues the namespaces found so far and reports the failure', :aggregate_failures do
      expect(usage_client).to receive(:get_session_namespaces).once.and_return(page(root_group, end_cursor: 'next'))
      expect(Gitlab::ErrorTracking).to receive(:track_exception)
        .with(an_instance_of(described_class::LookupOverTimeError), reason: 'over_time')
      expect(Gitlab::AppLogger).to receive(:warn).with(hash_including(
        Labkit::Fields::LOG_MESSAGE => 'Failed to list session namespaces from CustomersDot',
        Labkit::Fields::ERROR_TYPE => 'over_time'
      ))
      enqueued = enqueued_groups

      perform

      expect(enqueued).to contain_exactly(root_group)
      expect(counter).to have_received(:increment).with(reason: 'namespace_lookup_over_time')
      expect_logged(:stop_reason, :over_time)
    end

    it 'reports nothing when the last page arrives in time' do
      stub_pages(page(root_group))
      expect(Gitlab::ErrorTracking).not_to receive(:track_exception)

      perform

      expect(counter).not_to have_received(:increment)
      expect_logged(:stop_reason, :completed)
    end
  end

  it 'enqueues a namespace once when it comes back on a later page', :aggregate_failures do
    stub_pages(page(root_group, end_cursor: 'next'), page(root_group, other_root))
    enqueued = enqueued_groups

    perform

    expect(enqueued).to contain_exactly(root_group, other_root)
    expect_logged(:namespaces_enumerated, 2)
  end

  it 'skips a zero id and root namespaces that no longer exist', :aggregate_failures do
    stub_pages(page(0, non_existing_record_id, root_group))
    enqueued = enqueued_groups

    perform

    expect(enqueued).to contain_exactly(root_group)
    expect_logged(:namespaces_enumerated, 2)
    expect_logged(:namespaces_enqueued, 1)
  end

  it 'does not enqueue when CustomersDot billed nothing', :aggregate_failures do
    perform

    expect_nothing_enqueued
    expect_logged(:stop_reason, :completed)
  end

  it 'spreads the jobs one minute apart across the tick', :aggregate_failures do
    stub_pages(page(root_group, other_root, third_root))
    batches = enqueued_batches

    perform

    expect(batches.map(&:first)).to match_array([0, 60, 120])
    expect(batches.flat_map(&:last)).to contain_exactly(root_group, other_root, third_root)
  end

  it 'fills the spread window evenly when there are more namespaces than minutes', :aggregate_failures do
    stub_const("#{described_class}::SPREAD_MINUTES", 2)
    stub_pages(page(root_group, other_root, third_root))
    batches = enqueued_batches

    perform

    expect(batches.map(&:first)).to match_array([0, 60])
    expect(batches.map { |(_, groups)| groups.size }).to match_array([2, 1])
  end

  it 'uses every minute of the spread when namespaces outnumber minutes', :aggregate_failures do
    stub_const("#{described_class}::SPREAD_MINUTES", 3)
    stub_pages(page(root_group, other_root, third_root, fourth_root))
    batches = enqueued_batches

    perform

    expect(batches.map(&:first)).to match_array([0, 60, 120])
    expect(batches.map { |(_, groups)| groups.size }).to match_array([2, 1, 1])
  end

  it 'loads the groups in slices without dropping any', :aggregate_failures do
    stub_const("#{described_class}::GROUP_LOAD_BATCH_SIZE", 1)
    stub_pages(page(root_group, other_root))
    batches = enqueued_batches

    perform

    expect(batches.flat_map(&:last)).to contain_exactly(root_group, other_root)
    expect(batches.map(&:first)).to match_array([0, 60])
  end

  it 'logs the namespace jobs still buffered when the tick starts' do
    allow(Gitlab::SidekiqMiddleware::ConcurrencyLimit::ConcurrencyLimitService)
      .to receive(:queue_size).with(child_worker.name).and_return(3)

    perform

    expect_logged(:namespace_jobs_buffered, 3)
  end

  it 'preloads routes for the job contexts instead of one query per group' do
    stub_pages(page(root_group, other_root))
    enqueued_groups

    recorder = ActiveRecord::QueryRecorder.new { perform }

    expect(recorder.log.count { |sql| sql.include?('FROM "routes"') }).to be <= 1
  end

  shared_examples 'a failed namespace lookup' do |reason|
    it "enqueues nothing and logs #{reason}", :aggregate_failures do
      expect(Gitlab::AppLogger).to receive(:warn).with(hash_including(
        Labkit::Fields::LOG_MESSAGE => 'Failed to list session namespaces from CustomersDot',
        Labkit::Fields::ERROR_TYPE => reason.to_s
      ))

      perform

      expect_nothing_enqueued
      expect_logged(:stop_reason, :cdot_error)
    end

    it 'counts the failure' do
      counter = instance_double(Prometheus::Client::Counter)
      allow(Gitlab::Metrics).to receive(:counter).and_call_original
      allow(Gitlab::Metrics).to receive(:counter)
        .with(:duo_workflow_session_credits_v2_fetch_failures_total, anything).and_return(counter)
      expect(counter).to receive(:increment).with(reason: "namespace_lookup_#{reason}")

      perform
    end
  end

  context 'when CustomersDot returns an error' do
    before do
      allow(usage_client).to receive(:get_session_namespaces)
        .and_raise(client_error.new('nope', reason: :server_error))
    end

    it_behaves_like 'a failed namespace lookup', :server_error

    it 'does not report the error again, since the client already has' do
      expect(Gitlab::ErrorTracking).not_to receive(:track_exception)

      perform
    end
  end

  context 'when CustomersDot is unreachable' do
    before do
      allow(usage_client).to receive(:get_session_namespaces).and_raise(Errno::ECONNREFUSED)
    end

    it_behaves_like 'a failed namespace lookup', :connection_error

    it 'reports the error' do
      expect(Gitlab::ErrorTracking).to receive(:track_exception)
        .with(an_instance_of(Errno::ECONNREFUSED), reason: 'connection_error')

      perform
    end
  end

  context 'when a later page fails' do
    before do
      allow(usage_client).to receive(:get_session_namespaces).and_return(page(root_group, end_cursor: 'next'))
      allow(usage_client).to receive(:get_session_namespaces).with(hash_including(after: 'next'))
        .and_raise(client_error.new('nope', reason: :unavailable))
    end

    it_behaves_like 'a failed namespace lookup', :unavailable
  end

  context 'when a page says there is more but has no cursor' do
    before do
      stub_pages(page(root_group).deep_merge(page_info: { hasNextPage: true }))
    end

    it_behaves_like 'a failed namespace lookup', :malformed_response
  end

  describe 'freshness' do
    let(:freshness) { Ai::DuoWorkflows::SessionCredits::SyncFreshness }
    let(:stats) { { oldest_sync_age_s: 3600, oldest_awaiting_sync_s: 0, namespaces_awaiting_sync: 0 } }

    before do
      allow(freshness).to receive(:observe).and_return(stats)
      stub_pages(page(root_group, other_root))
    end

    it 'observes the namespaces in scope and logs the figures', :aggregate_failures do
      perform

      expect(freshness).to have_received(:observe).with(match_array([root_group.id, other_root.id])).once
      stats.each { |key, value| expect_logged(key, value) }
    end

    context 'when the freshness store fails' do
      let(:stats) { nil }

      it 'still enqueues the namespaces', :aggregate_failures do
        enqueued = enqueued_groups

        perform

        expect(enqueued).to contain_exactly(root_group, other_root)
        expect(worker).not_to have_received(:log_extra_metadata_on_done).with(:oldest_sync_age_s, anything)
      end
    end

    context 'when the CustomersDot lookup fails' do
      before do
        allow(usage_client).to receive(:get_session_namespaces)
          .and_raise(client_error.new('nope', reason: :server_error))
      end

      it 'observes nothing, since the scope is unknown' do
        perform

        expect(freshness).not_to have_received(:observe)
      end
    end

    context 'on self-managed' do
      before do
        allow(Gitlab::Saas).to receive(:feature_available?).with(:gitlab_com_subscriptions).and_return(false)
      end

      it 'observes nothing, since only GitLab.com namespaces are tracked' do
        perform

        expect(freshness).not_to have_received(:observe)
      end
    end
  end

  context 'when ClickHouse analytics is disabled' do
    before do
      allow(Gitlab::ClickHouse).to receive(:globally_enabled_for_analytics?).and_return(false)
    end

    it 'does nothing' do
      expect(usage_client).not_to receive(:get_session_namespaces)

      perform

      expect_nothing_enqueued
    end
  end

  context 'on self-managed' do
    before do
      allow(Gitlab::Saas).to receive(:feature_available?).with(:gitlab_com_subscriptions).and_return(false)
    end

    it 'enqueues one instance-level job without calling CustomersDot', :aggregate_failures do
      expect(Gitlab::SubscriptionPortal::SubscriptionUsageClient).not_to receive(:new)

      perform

      expect(child_worker).to have_received(:perform_async).with(nil)
      expect_logged(:namespaces_enumerated, 1)
      expect_logged(:namespaces_enqueued, 1)
    end
  end

  describe 'worker attributes' do
    it 'registers with ClickHouse migration pause control and disables retries', :aggregate_failures do
      expect(described_class.click_house_worker_attrs).to be_present
      expect(described_class.sidekiq_options['retry']).to be(false)
      expect(described_class.get_data_consistency_per_database.values.uniq).to eq([:sticky])
      expect(described_class.get_deduplicate_strategy).to eq(:until_executed)
    end
  end
end
