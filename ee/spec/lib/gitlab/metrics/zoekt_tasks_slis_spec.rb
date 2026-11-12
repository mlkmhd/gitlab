# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Gitlab::Metrics::ZoektTasksSlis, :prometheus, feature_category: :global_search do
  describe '#initialize_slis!' do
    it 'initializes Apdex SLI for search_zoekt_tasks' do
      expect(Gitlab::Metrics::Sli::Apdex).to receive(:initialize_sli).with(:search_zoekt_tasks, [])

      described_class.initialize_slis!
    end

    it 'initializes ErrorRate SLI for search_zoekt_tasks' do
      expect(Gitlab::Metrics::Sli::ErrorRate).to receive(:initialize_sli).with(:search_zoekt_tasks, [])

      described_class.initialize_slis!
    end
  end

  describe '#increment_request_count' do
    let(:zoekt_node_id) { 1 }
    let(:task_type) { 'index' }

    it 'increments the request counter with correct labels' do
      counter = instance_double(Prometheus::Client::Counter)
      allow(described_class).to receive(:request_counter).and_return(counter)

      expect(counter).to receive(:increment).with(
        { zoekt_node: '1', task_type: 'index' },
        1
      )

      described_class.increment_request_count(zoekt_node_id: zoekt_node_id, task_type: task_type)
    end

    it 'increments by custom count when provided' do
      counter = instance_double(Prometheus::Client::Counter)
      allow(described_class).to receive(:request_counter).and_return(counter)

      expect(counter).to receive(:increment).with(
        { zoekt_node: '1', task_type: 'index' },
        5
      )

      described_class.increment_request_count(zoekt_node_id: zoekt_node_id, task_type: task_type, count: 5)
    end
  end

  describe '#increment_error_count' do
    let(:zoekt_node_id) { 2 }
    let(:task_type) { 'delete' }

    it 'increments the error rate SLI with correct labels' do
      expect(Gitlab::Metrics::Sli::ErrorRate[:search_zoekt_tasks]).to receive(:increment).with(
        labels: { zoekt_node: '2', task_type: 'delete' },
        error: true
      )

      described_class.increment_error_count(zoekt_node_id: zoekt_node_id, task_type: task_type)
    end
  end

  describe '#increment_apdex' do
    let(:zoekt_node_id) { 3 }
    let(:task_type) { 'index' }
    let(:labels) { { zoekt_node: '3', task_type: 'index' } }

    before do
      allow(Gitlab::Metrics::Sli::Apdex[:search_zoekt_tasks]).to receive(:increment)
      allow(Gitlab::AppJsonLogger).to receive(:info)
    end

    context 'when duration is within threshold' do
      it 'increments apdex as success' do
        duration = described_class::APDEX_THRESHOLD_S - 100

        expect(Gitlab::Metrics::Sli::Apdex[:search_zoekt_tasks]).to receive(:increment).with(
          labels: labels,
          success: true
        )

        described_class.increment_apdex(zoekt_node_id: zoekt_node_id, task_type: task_type, duration: duration)
      end
    end

    context 'when duration exceeds threshold' do
      it 'increments apdex as failure' do
        duration = described_class::APDEX_THRESHOLD_S + 100

        expect(Gitlab::Metrics::Sli::Apdex[:search_zoekt_tasks]).to receive(:increment).with(
          labels: labels,
          success: false
        )

        described_class.increment_apdex(zoekt_node_id: zoekt_node_id, task_type: task_type, duration: duration)
      end
    end

    context 'when duration equals threshold' do
      it 'increments apdex as success' do
        duration = described_class::APDEX_THRESHOLD_S

        expect(Gitlab::Metrics::Sli::Apdex[:search_zoekt_tasks]).to receive(:increment).with(
          labels: labels,
          success: true
        )

        described_class.increment_apdex(zoekt_node_id: zoekt_node_id, task_type: task_type, duration: duration)
      end
    end

    describe 'duration histogram' do
      let(:histogram) { instance_double(Prometheus::Client::Histogram, observe: nil) }

      before do
        allow(described_class).to receive(:duration_histogram).and_return(histogram)
      end

      it 'observes the duration with the apdex labels, at full sub-second resolution' do
        expect(histogram).to receive(:observe).with(labels, 45.25)

        described_class.increment_apdex(zoekt_node_id: zoekt_node_id, task_type: task_type, duration: 45.25)
      end

      it 'observes a duration that exceeds the apdex threshold' do
        expect(histogram).to receive(:observe).with(labels, 9000.5)

        described_class.increment_apdex(zoekt_node_id: zoekt_node_id, task_type: task_type, duration: 9000.5)
      end
    end

    describe 'histogram buckets' do
      it 'includes an exact 60 second edge' do
        expect(described_class::DURATION_BUCKETS).to include(60)
      end

      it 'declares monotonically increasing buckets' do
        expect(described_class::DURATION_BUCKETS).to eq(described_class::DURATION_BUCKETS.sort.uniq)
      end

      it 'declares integer edges so the exporter renders le="60", not le="60.0"' do
        expect(described_class::DURATION_BUCKETS).to all(be_an(Integer))
      end

      it 'registers the histogram with those buckets' do
        expect(Gitlab::Metrics).to receive(:histogram).with(
          :gitlab_search_zoekt_task_duration_seconds,
          anything,
          {},
          described_class::DURATION_BUCKETS
        ).and_return(instance_double(Prometheus::Client::Histogram, observe: nil))

        described_class.increment_apdex(zoekt_node_id: zoekt_node_id, task_type: task_type, duration: 1.0)
      end

      it 'extends beyond the apdex threshold so an outlier is not collapsed into +Inf' do
        expect(described_class::DURATION_BUCKETS.max).to be > described_class::APDEX_THRESHOLD_S
      end

      it 'includes the apdex threshold as an exact edge so the apdex ratio is re-derivable' do
        expect(described_class::DURATION_BUCKETS).to include(described_class::APDEX_THRESHOLD_S)
      end
    end

    # Prometheus normalizes `le` to canonical float form on ingest, so a bare
    # integer matcher selects nothing and returns an empty result rather than an
    # error. The guard is on the documented queries themselves.
    describe 'documented PromQL queries' do
      let(:doc_path) { Rails.root.join('doc/development/application_slis/zoekt_tasks.md') }
      let(:promql_blocks) do
        doc_path.read.scan(/^```promql\n(.*?)^```/m).flatten
      end

      it 'documents at least one query per metric surface' do
        expect(promql_blocks.size).to be >= 3
      end

      it 'never matches an integer-valued bucket edge with a bare le="N"' do
        offenders = promql_blocks.flat_map { |b| b.scan(/le="(\d+)"/) }.flatten

        expect(offenders).to be_empty,
          "bare integer `le` matchers select nothing once Prometheus canonicalizes " \
            "the label to float form; use le=~\"N(\\\\.0+)?\". Found: #{offenders.inspect}"
      end

      it 'never ships an invalid PromQL string escape in a le=~ regex matcher' do
        # PromQL requires a literal backslash inside a double-quoted string to be
        # written `\\`, so `\.` (single backslash) is an invalid escape sequence
        # and fails to parse; `\\.` (escaped backslash, literal dot) is valid.
        offenders = promql_blocks.flat_map { |b| b.scan(/le=~"[^"]*"/) }
          .select { |m| m.gsub('\\\\', '').include?('\.') }

        expect(offenders).to be_empty,
          "a single backslash before `.` is not a valid PromQL string escape " \
            "and fails to parse; use `\\\\.` instead. Found: #{offenders.inspect}"
      end
    end

    describe 'structured log line' do
      let(:histogram) { instance_double(Prometheus::Client::Histogram, observe: nil) }

      before do
        allow(described_class).to receive(:duration_histogram).and_return(histogram)
      end

      it 'logs the duration, target, outcome and labels' do
        expect(Gitlab::AppJsonLogger).to receive(:info).with(
          message: 'Zoekt task Apdex SLI',
          ::Labkit::Fields::DURATION_S => 45.25,
          target_s: described_class::APDEX_THRESHOLD_S,
          success: true,
          zoekt_node: '3',
          task_type: 'index'
        )

        described_class.increment_apdex(zoekt_node_id: zoekt_node_id, task_type: task_type, duration: 45.25)
      end

      it 'logs success false when the duration exceeds the threshold' do
        expect(Gitlab::AppJsonLogger).to receive(:info).with(
          hash_including(success: false, ::Labkit::Fields::DURATION_S => 9000.5)
        )

        described_class.increment_apdex(zoekt_node_id: zoekt_node_id, task_type: task_type, duration: 9000.5)
      end

      it 'carries the split terms when a start instant was derivable' do
        expect(Gitlab::AppJsonLogger).to receive(:info).with(
          hash_including(queue_wait_s: 40.0, processing_s: 5.25)
        )

        described_class.increment_apdex(
          zoekt_node_id: zoekt_node_id, task_type: task_type,
          duration: 45.25, queue_wait: 40.0, processing: 5.25
        )
      end

      # A zero is a real measurement, so the fields must be absent rather than
      # defaulted when the split was skipped.
      it 'omits both split terms when no start instant was derivable' do
        expect(Gitlab::AppJsonLogger).to receive(:info) do |payload|
          expect(payload).not_to have_key(:queue_wait_s)
          expect(payload).not_to have_key(:processing_s)
          expect(payload).to include(::Labkit::Fields::DURATION_S => 45.25)
        end

        described_class.increment_apdex(zoekt_node_id: zoekt_node_id, task_type: task_type, duration: 45.25)
      end

      it 'omits both when only one term is present, so a half pair never logs' do
        expect(Gitlab::AppJsonLogger).to receive(:info) do |payload|
          expect(payload).not_to have_key(:queue_wait_s)
          expect(payload).not_to have_key(:processing_s)
        end

        described_class.increment_apdex(
          zoekt_node_id: zoekt_node_id, task_type: task_type, duration: 45.25, queue_wait: 40.0
        )
      end

      it 'logs a split pair that sums to the logged duration' do
        expect(Gitlab::AppJsonLogger).to receive(:info) do |payload|
          expect(payload[:queue_wait_s] + payload[:processing_s])
            .to be_within(0.001).of(payload[::Labkit::Fields::DURATION_S])
        end

        described_class.increment_apdex(
          zoekt_node_id: zoekt_node_id, task_type: task_type,
          duration: 45.25, queue_wait: 40.0, processing: 5.25
        )
      end
    end
  end

  describe 'QUEUE_DURATION_BUCKETS' do
    subject(:buckets) { described_class::QUEUE_DURATION_BUCKETS }

    it 'contains 60 exactly, so a 60-second objective needs no interpolation' do
      expect(buckets).to include(60)
    end

    it 'has the declared edges and no others' do
      expect(buckets).to eq([1, 5, 10, 30, 60, 120, 300, 600, 1800, 3600, 7200, 21600])
    end

    it 'is sorted ascending and free of duplicates' do
      expect(buckets).to eq(buckets.sort.uniq)
    end
  end

  describe 'PROCESSING_DURATION_BUCKETS' do
    subject(:buckets) { described_class::PROCESSING_DURATION_BUCKETS }

    it 'has the declared edges and no others' do
      expect(buckets).to eq([0.1, 0.5, 1, 5, 10, 30, 60, 300, 900, 1800, 3600])
    end

    it 'resolves below one second, where nearly all tasks finish' do
      expect(buckets.count { |edge| edge < 1 }).to be >= 2
    end

    it 'is sorted ascending and free of duplicates' do
      expect(buckets).to eq(buckets.sort.uniq)
    end
  end

  describe '#observe_queue_duration' do
    let(:histogram) { described_class.send(:queue_duration_histogram) }

    # `get` returns the declared edges only. The `+Inf` series the exposition
    # carries is synthesised by the formatter from `_count`, not held as a key
    # here, so `eq` on the constant is exact rather than off by one.
    it 'registers the histogram with an exact 60 bucket edge' do
      edges = histogram.get({ zoekt_node: '6', task_type: 'index_repo' }).keys

      expect(edges).to eq(described_class::QUEUE_DURATION_BUCKETS)
      expect(edges).to include(60)
    end

    it 'observes the duration with both labels' do
      expect(histogram).to receive(:observe).with({ zoekt_node: '7', task_type: 'index_repo' }, 45.0)
      allow(described_class).to receive(:queue_duration_histogram).and_return(histogram)

      described_class.observe_queue_duration(zoekt_node_id: 7, task_type: :index_repo, duration: 45.0)
    end

    it 'counts a 45-second wait at le=60 and above, and not at le=30' do
      described_class.observe_queue_duration(zoekt_node_id: 8, task_type: :index_repo, duration: 45.0)

      buckets = histogram.get({ zoekt_node: '8', task_type: 'index_repo' })

      expect(buckets[30]).to eq(0)
      expect(buckets[60]).to eq(1)
      expect(buckets[120]).to eq(1)
    end
  end

  describe '#observe_processing_duration' do
    let(:histogram) { described_class.send(:processing_duration_histogram) }

    it 'registers the histogram with the declared edges' do
      edges = histogram.get({ zoekt_node: '6', task_type: 'index_repo' }).keys

      expect(edges).to eq(described_class::PROCESSING_DURATION_BUCKETS)
    end

    it 'counts a 0.4-second run at le=0.5 and not at le=0.1' do
      described_class.observe_processing_duration(zoekt_node_id: 9, task_type: :index_repo, duration: 0.4)

      buckets = histogram.get({ zoekt_node: '9', task_type: 'index_repo' })

      expect(buckets[0.1]).to eq(0)
      expect(buckets[0.5]).to eq(1)
    end
  end

  # A retry rewrites `perform_at` into the future, so a callback can compute a
  # negative interval, which would decrement the histogram's `_sum`.
  describe 'negative durations' do
    let(:labels) { { zoekt_node: '11', task_type: 'index_repo' } }
    let(:histogram) { instance_double(Prometheus::Client::Histogram, observe: nil) }

    it 'floors the total-duration observation at zero' do
      allow(Gitlab::Metrics::Sli::Apdex[:search_zoekt_tasks]).to receive(:increment)
      allow(Gitlab::AppJsonLogger).to receive(:info)
      allow(described_class).to receive(:duration_histogram).and_return(histogram)

      expect(histogram).to receive(:observe).with(labels, 0)

      described_class.increment_apdex(zoekt_node_id: 11, task_type: :index_repo, duration: -12.5)
    end

    it 'floors the queue-wait observation at zero' do
      allow(described_class).to receive(:queue_duration_histogram).and_return(histogram)

      expect(histogram).to receive(:observe).with(labels, 0)

      described_class.observe_queue_duration(zoekt_node_id: 11, task_type: :index_repo, duration: -12.5)
    end

    it 'floors the processing observation at zero' do
      allow(described_class).to receive(:processing_duration_histogram).and_return(histogram)

      expect(histogram).to receive(:observe).with(labels, 0)

      described_class.observe_processing_duration(zoekt_node_id: 11, task_type: :index_repo, duration: -0.75)
    end

    # The floor must not round a real sub-second measurement.
    it 'passes a small positive duration through unchanged' do
      allow(described_class).to receive(:processing_duration_histogram).and_return(histogram)

      expect(histogram).to receive(:observe).with(labels, 0.25)

      described_class.observe_processing_duration(zoekt_node_id: 11, task_type: :index_repo, duration: 0.25)
    end

    # The raw value survives outside the histogram: the floor protects `_sum`,
    # and the log line is the only signal a retry raced its own callback.
    it 'still scores the apdex and logs the raw negative duration' do
      allow(described_class).to receive(:duration_histogram).and_return(histogram)
      allow(Gitlab::Metrics::Sli::Apdex[:search_zoekt_tasks]).to receive(:increment)

      expect(Gitlab::AppJsonLogger).to receive(:info).with(
        hash_including(success: true, ::Labkit::Fields::DURATION_S => -12.5)
      )

      described_class.increment_apdex(zoekt_node_id: 11, task_type: :index_repo, duration: -12.5)
    end

    # The three above assert the ARGUMENT on a double. These assert the EFFECT
    # on the real registered histogram, which is the quantity that corrupts: a
    # negative observation decrements `_sum` while `_count` still rises.
    it 'never decreases the queue-wait _sum' do
      real = described_class.send(:queue_duration_histogram)
      sum = -> { real.values[{ zoekt_node: '12', task_type: 'index_repo' }].sum.get }

      described_class.observe_queue_duration(zoekt_node_id: 12, task_type: :index_repo, duration: 30)
      before_sum = sum.call

      described_class.observe_queue_duration(zoekt_node_id: 12, task_type: :index_repo, duration: -900)

      expect(sum.call).to eq(before_sum)
    end

    it 'never decreases the processing _sum' do
      real = described_class.send(:processing_duration_histogram)
      sum = -> { real.values[{ zoekt_node: '13', task_type: 'index_repo' }].sum.get }

      described_class.observe_processing_duration(zoekt_node_id: 13, task_type: :index_repo, duration: 5)
      before_sum = sum.call

      described_class.observe_processing_duration(zoekt_node_id: 13, task_type: :index_repo, duration: -900)

      expect(sum.call).to eq(before_sum)
    end
  end
end
