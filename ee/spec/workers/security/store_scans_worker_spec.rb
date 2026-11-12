# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Security::StoreScansWorker, feature_category: :vulnerability_management do
  let_it_be(:sast_scan) { create(:security_scan, scan_type: :sast) }
  let_it_be(:pipeline) { sast_scan.pipeline }
  let_it_be(:sast_build) { pipeline.security_scans.sast.last&.build }

  it 'retries up to 5 times' do
    expect(described_class.get_sidekiq_options['retry']).to eq(5)
  end

  describe 'deferring on database health' do
    it 'watches the sec tables written by StoreScansService' do
      expect(described_class.database_health_check_attrs).to include(
        gitlab_schema: :gitlab_sec,
        tables: %w[security_scans security_findings security_finding_enrichments],
        delay_by: 1.minute
      )
    end

    it 'defers when the feature flag is enabled' do
      expect(described_class.defer_on_database_health_signal?).to be(true)
    end

    context 'when the feature flag is disabled' do
      before do
        stub_feature_flags(defer_store_scans_on_database_health: false)
      end

      it 'does not defer' do
        expect(described_class.defer_on_database_health_signal?).to be(false)
      end
    end
  end

  describe '.sidekiq_retry_in_block' do
    using RSpec::Parameterized::TableSyntax

    subject(:retry_in) { described_class.sidekiq_retry_in_block.call(count, exception, {}) }

    context 'when another job holds the store lease' do
      let(:exception) { Security::StoreGroupedScansService::LeaseTakenError.new }

      where(:count, :delay) do
        0 | 1.minute
        1 | 2.minutes
        2 | 4.minutes
        3 | 8.minutes
        4 | 16.minutes
      end

      with_them do
        it { is_expected.to eq(delay.to_i) }
      end
    end

    context 'for any other error' do
      let(:count) { 0 }
      let(:exception) { StandardError.new }

      it { is_expected.to be_nil }
    end
  end

  describe '#perform' do
    subject(:run_worker) { described_class.new.perform(pipeline.id) }

    before do
      allow(Security::StoreScansService).to receive(:execute)
      allow_next_found_instance_of(Ci::Pipeline) do |record|
        allow(record).to receive_message_chain(:project,
          :can_store_security_reports?).and_return(can_store_security_reports)
      end
    end

    context 'when security reports can not be stored for the pipeline' do
      let(:can_store_security_reports) { false }

      it 'does not call `Security::StoreScansService`' do
        run_worker

        expect(Security::StoreScansService).not_to have_received(:execute)
      end
    end

    context 'when security reports can be stored for the pipeline' do
      let(:can_store_security_reports) { true }

      it 'calls `Security::StoreScansService`' do
        run_worker

        expect(Security::StoreScansService).to have_received(:execute)
      end
    end
  end
end
