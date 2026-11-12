# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Gitlab::Metrics::ZoektRolloutSlis, feature_category: :global_search do
  let(:counter) { instance_double(Prometheus::Client::Counter, increment: nil) }

  before do
    allow(Gitlab::Metrics).to receive(:counter)
      .with(:search_zoekt_rollout_planning_failures_total, anything)
      .and_return(counter)
  end

  describe '.initialize_slis!' do
    it 'creates the series at zero' do
      described_class.initialize_slis!

      expect(counter).to have_received(:increment).with({}, 0)
    end
  end

  describe '.increment_planning_failure' do
    it 'increments the counter' do
      described_class.increment_planning_failure

      expect(counter).to have_received(:increment).with({}, 1)
    end
  end

  it 'is enabled only in Sidekiq' do
    registered = Gitlab::Metrics::SliConfig.registered_classes.select { |c| c.klass == described_class }

    allow(Gitlab::Runtime).to receive_messages(sidekiq?: true, puma?: false)
    expect(registered.filter_map(&:enabled_class)).to eq([described_class])

    allow(Gitlab::Runtime).to receive_messages(sidekiq?: false, puma?: true)
    expect(registered.filter_map(&:enabled_class)).to be_empty
  end
end
