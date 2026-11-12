# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Analytics::UsageTrends::CounterJobWorker, feature_category: :devops_reports do
  let_it_be(:user_1) { create(:user) }
  let_it_be(:user_2) { create(:user) }

  let(:users_measurement_identifier) { ::Analytics::UsageTrends::Measurement.identifiers.fetch(:users) }
  let(:recorded_at) { Time.zone.now }
  let(:job_args) { [users_measurement_identifier, user_1.id, user_2.id, recorded_at.iso8601] }

  before do
    allow(::ApplicationRecord.connection).to receive(:transaction_open?).and_return(false)
    allow(::Ci::ApplicationRecord.connection).to receive(:transaction_open?).and_return(false) if ::Ci::ApplicationRecord.connection_class?
  end

  include_examples 'an idempotent worker' do
    it 'counts a scope and stores the result' do
      subject

      measurement = Analytics::UsageTrends::Measurement.users.first
      expect(measurement.recorded_at).to be_like_time(recorded_at)
      expect(measurement.identifier).to eq('users')
      expect(measurement.count).to eq(2)
    end
  end

  context 'when no records are in the database' do
    let(:users_measurement_identifier) { ::Analytics::UsageTrends::Measurement.identifiers.fetch(:groups) }

    subject { described_class.new.perform(users_measurement_identifier, nil, nil, recorded_at.iso8601) }

    it 'sets 0 as the count' do
      subject

      measurement = Analytics::UsageTrends::Measurement.groups.first
      expect(measurement.recorded_at).to be_like_time(recorded_at)
      expect(measurement.identifier).to eq('groups')
      expect(measurement.count).to eq(0)
    end
  end

  it 'does not raise error when inserting duplicated measurement' do
    subject

    expect { subject }.not_to raise_error
  end

  it 'does not count a dropped measurement for a completed count' do
    expect(Gitlab::Metrics).not_to receive(:counter).with(:gitlab_usage_trends_measurement_dropped_total, anything)

    subject
  end

  context 'when the batch counter drops the measurement' do
    using RSpec::Parameterized::TableSyntax

    let(:worker) { described_class.new }
    let(:counter) { instance_double(Prometheus::Client::Counter) }

    subject(:perform) { worker.perform(*job_args) }

    before do
      allow(Gitlab::Database::BatchCount).to receive(:batch_count_with_timeout).and_return({ status: status })
      allow(Gitlab::Metrics).to receive(:counter).and_call_original
      allow(Gitlab::Metrics).to receive(:counter)
        .with(:gitlab_usage_trends_measurement_dropped_total, anything).and_return(counter)
      allow(counter).to receive(:increment)
      allow(worker).to receive(:log_extra_metadata_on_done)
    end

    where(:status) do
      [[:bad_config], [:cancelled]]
    end

    with_them do
      it 'does not insert a measurement' do
        expect { perform }.not_to change { Analytics::UsageTrends::Measurement.count }
      end

      it 'adds the identifier, outcome, range and recorded_at to the done log', :aggregate_failures do
        perform

        expect(worker).to have_received(:log_extra_metadata_on_done)
          .with(:measurement_identifier, users_measurement_identifier)
        expect(worker).to have_received(:log_extra_metadata_on_done).with(:drop_reason, status.to_s)
        expect(worker).to have_received(:log_extra_metadata_on_done).with(:measurement, 'users')
        expect(worker).to have_received(:log_extra_metadata_on_done).with(:min_id, user_1.id)
        expect(worker).to have_received(:log_extra_metadata_on_done).with(:max_id, user_2.id)
        expect(worker).to have_received(:log_extra_metadata_on_done).with(:recorded_at, recorded_at.iso8601)
      end

      it 'increments the dropped measurement counter with the outcome as reason' do
        perform

        expect(counter).to have_received(:increment).with(reason: status.to_s)
      end
    end
  end

  context 'when the timeout elapses' do
    let(:min_id) { 1 }
    let(:max_id) { 12345 }
    let(:continue_from) { 321 }
    let(:partial_results) { 42 }
    let(:final_count) { 123 }

    subject { described_class.new.perform(users_measurement_identifier, min_id, max_id, recorded_at.iso8601) }

    it 'continues counting later when the timeout elapses' do
      expect(Gitlab::Database::BatchCount).to receive(:batch_count_with_timeout)
        .with(anything, start: min_id, finish: max_id, timeout: 250.seconds, partial_results: nil)
        .and_return({ status: :timeout, partial_results: partial_results, continue_from: continue_from })

      expect(described_class).to receive(:perform_async).with(anything, continue_from, max_id, recorded_at.iso8601, partial_results) do |*args|
        described_class.new.perform(*args)
      end

      expect(Gitlab::Database::BatchCount).to receive(:batch_count_with_timeout)
        .with(anything, start: continue_from, finish: max_id, timeout: 250.seconds, partial_results: partial_results)
        .and_return({ status: :completed, count: final_count })

      expect { subject }.to change { Analytics::UsageTrends::Measurement.count }

      measurement = Analytics::UsageTrends::Measurement.users.last
      expect(measurement.recorded_at).to be_like_time(recorded_at)
      expect(measurement.identifier).to eq('users')
      expect(measurement.count).to eq(final_count)
    end
  end

  context 'when pipelines_succeeded identifier is passed' do
    let_it_be(:pipeline) { create(:ci_pipeline, :success) }

    let(:successful_pipelines_measurement_identifier) { ::Analytics::UsageTrends::Measurement.identifiers.fetch(:pipelines_succeeded) }
    let(:job_args) { [successful_pipelines_measurement_identifier, pipeline.id, pipeline.id, recorded_at.iso8601] }

    it 'counts successful pipelines' do
      subject

      measurement = Analytics::UsageTrends::Measurement.pipelines_succeeded.first
      expect(measurement.recorded_at).to be_like_time(recorded_at)
      expect(measurement.identifier).to eq('pipelines_succeeded')
      expect(measurement.count).to eq(1)
    end
  end

  context 'when issues identifier is passed' do
    let_it_be(:group_work_item) { create(:work_item, :group_level) }
    let_it_be(:project_work_item) { create(:work_item) }

    let(:issues_identifier) { ::Analytics::UsageTrends::Measurement.identifiers.fetch(:issues) }
    let(:job_args) { [issues_identifier, group_work_item.id, project_work_item.id, recorded_at.iso8601] }

    it 'does not count group level work items' do
      subject

      measurement = Analytics::UsageTrends::Measurement.issues.first
      expect(measurement.recorded_at).to be_like_time(recorded_at)
      expect(measurement.identifier).to eq('issues')
      expect(measurement.count).to eq(1)
    end
  end
end
