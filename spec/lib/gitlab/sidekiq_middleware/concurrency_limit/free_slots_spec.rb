# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Gitlab::SidekiqMiddleware::ConcurrencyLimit::FreeSlots, feature_category: :scalability do
  let(:worker_class) do
    Class.new do
      def self.name
        'TestFreeSlotsWorker'
      end

      include ApplicationWorker

      concurrency_limit -> { 10 }
    end
  end

  before do
    stub_const('TestFreeSlotsWorker', worker_class)
  end

  describe '.enabled_for?' do
    subject(:enabled) { described_class.enabled_for?(worker_class) }

    it { is_expected.to be(true) }

    it 'checks the worker flag against the instance' do
      allow(Feature).to receive(:enabled?).and_call_original
      expect(Feature).to receive(:enabled?)
        .with(:sidekiq_concurrency_limit_use_free_slots_TestFreeSlotsWorker, :instance,
          type: :worker, default_enabled_if_undefined: false).and_call_original

      enabled
    end

    context 'when the worker flag is disabled' do
      before do
        stub_feature_flags(sidekiq_concurrency_limit_use_free_slots_TestFreeSlotsWorker: false)
      end

      it { is_expected.to be(false) }
    end

    context 'when sidekiq_concurrency_limit_middleware is disabled' do
      before do
        stub_feature_flags(sidekiq_concurrency_limit_middleware: false)
      end

      it { is_expected.to be(false) }
    end

    context 'without a worker class' do
      subject(:enabled) { described_class.enabled_for?(nil) }

      it { is_expected.to be(false) }
    end
  end

  describe '.admission_limit' do
    it 'is the limit while the deferred list is empty' do
      expect(described_class.admission_limit(10, nil)).to eq(10)
    end

    it 'is the limit while the oldest deferred job is younger than the age cap' do
      expect(described_class.admission_limit(10, 1.minute.ago.to_f)).to eq(10)
    end

    it 'keeps a reserve free once the oldest deferred job is past the age cap', :aggregate_failures do
      expect(described_class.admission_limit(10, 6.minutes.ago.to_f)).to eq(9)
      expect(described_class.admission_limit(25, 6.minutes.ago.to_f)).to eq(22)
    end

    it 'reserves at least one slot' do
      expect(described_class.admission_limit(1, 6.minutes.ago.to_f)).to eq(0)
    end

    it 'leaves a non-positive limit alone', :aggregate_failures do
      expect(described_class.admission_limit(0, 6.minutes.ago.to_f)).to eq(0)
      expect(described_class.admission_limit(-1, 6.minutes.ago.to_f)).to eq(-1)
    end
  end
end
