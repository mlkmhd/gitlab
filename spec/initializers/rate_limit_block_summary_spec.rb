# frozen_string_literal: true

require 'fast_spec_helper'
require 'labkit/rate_limit'

RSpec.describe 'rate limit block summary initializer', feature_category: :rate_limiting do
  let(:background_task) { instance_double(Gitlab::BackgroundTask) }
  let(:summary) { instance_double(Labkit::RateLimit::BlockSummary) }

  subject(:run_initializer) do
    load rails_root_join('config/initializers/rate_limit_block_summary.rb')
  end

  context 'when puma' do
    before do
      allow(Gitlab::Runtime).to receive(:puma?).and_return(true)
      allow(Gitlab::Cluster::LifecycleEvents).to receive(:on_worker_start).and_yield
      allow(Gitlab::Middleware::LabkitRackRateLimit).to receive(:block_summary).and_return(summary)
      allow(Gitlab::BackgroundTask).to receive(:new)
        .with(summary, name: 'rate_limit_block_summary')
        .and_return(background_task)
    end

    it 'starts the summary on worker start and stops it on worker stop', :aggregate_failures do
      expect(background_task).to receive(:start).and_return(background_task)
      expect(Gitlab::Cluster::LifecycleEvents).to receive(:on_worker_stop).and_yield
      expect(background_task).to receive(:stop)

      run_initializer
    end
  end

  context 'when not puma' do
    before do
      allow(Gitlab::Runtime).to receive(:puma?).and_return(false)
    end

    it 'registers nothing' do
      expect(Gitlab::Cluster::LifecycleEvents).not_to receive(:on_worker_start)

      run_initializer
    end
  end
end
