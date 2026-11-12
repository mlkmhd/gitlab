# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Issuables::ScheduleCsvExportService, feature_category: :team_planning do
  let_it_be(:user) { create(:user) }
  let_it_be(:project) { create(:project) }

  let(:params) { { 'state' => 'opened' } }

  subject(:execute) { schedule_export }

  def schedule_export
    described_class.new(type: :issue, current_user: user, project: project, params: params).execute
  end

  it 'schedules the export' do
    expect(IssuableExportCsvWorker).to receive(:perform_async).with(:issue, user.id, project.id, params)

    execute
  end

  context 'when the user is over the rate limit' do
    before do
      allow(Gitlab::ApplicationRateLimiter).to receive(:throttled?)
        .with(:issuable_csv_export, scope: { user: user })
        .and_return(true)
    end

    it 'raises a rate limit error and does not schedule the export', :aggregate_failures do
      expect(IssuableExportCsvWorker).not_to receive(:perform_async)

      expect { execute }.to raise_error(RateLimitedService::RateLimitedError)
    end
  end

  context 'when the user reaches the limit', :freeze_time, :clean_gitlab_redis_rate_limiting do
    it 'raises a rate limit error after 20 exports in an hour', :aggregate_failures do
      allow(IssuableExportCsvWorker).to receive(:perform_async)
      20.times { schedule_export }

      expect { schedule_export }.to raise_error(RateLimitedService::RateLimitedError)
      expect(IssuableExportCsvWorker).to have_received(:perform_async).exactly(20).times
    end

    it 'counts exports over one hour' do
      expect(Gitlab::ApplicationRateLimiter.period_for(:issuable_csv_export)).to eq(1.hour)
    end
  end

  context 'when issuable_csv_export_rate_limit is disabled' do
    before do
      stub_feature_flags(issuable_csv_export_rate_limit: false)
    end

    it 'schedules the export without checking the rate limit', :aggregate_failures do
      expect(Gitlab::ApplicationRateLimiter).not_to receive(:throttled?)
      expect(IssuableExportCsvWorker).to receive(:perform_async)

      execute
    end
  end
end
