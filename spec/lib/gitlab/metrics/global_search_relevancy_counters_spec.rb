# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Gitlab::Metrics::GlobalSearchRelevancyCounters, feature_category: :global_search do
  let(:requests_counter) { instance_double(Prometheus::Client::Counter, increment: nil) }
  let(:result_clicks_counter) { instance_double(Prometheus::Client::Counter, increment: nil) }

  before do
    # Clear memoization so the stubbed Gitlab::Metrics.counter below is
    # actually consulted, instead of a counter memoized by an earlier example.
    described_class.clear_memoization(:requests_counter)
    described_class.clear_memoization(:result_clicks_counter)

    allow(Gitlab::Metrics).to receive(:counter).with(
      :gitlab_global_search_requests_total, anything
    ).and_return(requests_counter)
    allow(Gitlab::Metrics).to receive(:counter).with(
      :gitlab_global_search_result_clicks_total, anything
    ).and_return(result_clicks_counter)
  end

  after do
    described_class.clear_memoization(:requests_counter)
    described_class.clear_memoization(:result_clicks_counter)
  end

  describe '.record_search' do
    it 'increments the requests counter with a clamped search_type and the zero_results label' do
      described_class.record_search(search_type: 'basic', scope: 'issues', zero_results: true, source: 'web')

      expect(requests_counter).to have_received(:increment).with(
        search_type: 'basic', scope: 'issues', zero_results: 'true', source: 'web'
      )
    end

    it 'clamps an unrecognised search_type to nil rather than minting an unbounded label' do
      described_class.record_search(search_type: 'not-a-real-type', scope: 'issues', zero_results: false, source: 'api')

      expect(requests_counter).to have_received(:increment).with(
        search_type: nil, scope: 'issues', zero_results: 'false', source: 'api'
      )
    end

    it 'clamps an unrecognised source to nil rather than minting an unbounded label' do
      described_class.record_search(search_type: 'basic', scope: 'issues', zero_results: false, source: 'bogus')

      expect(requests_counter).to have_received(:increment).with(
        search_type: 'basic', scope: 'issues', zero_results: 'false', source: nil
      )
    end

    it 'clamps an unrecognised scope to nil rather than minting an unbounded series' do
      described_class.record_search(search_type: 'basic', scope: 'not-a-real-scope', zero_results: false, source: 'web')

      expect(requests_counter).to have_received(:increment).with(
        search_type: 'basic', scope: nil, zero_results: 'false', source: 'web'
      )
    end
  end

  describe '.record_result_click' do
    it 'buckets position 1 as "1"' do
      described_class.record_result_click(search_type: 'basic', scope: 'blobs', position: 1)

      expect(result_clicks_counter).to have_received(:increment).with(
        search_type: 'basic', scope: 'blobs', position_bucket: '1'
      )
    end

    it 'buckets positions 2 and 3 as "2-3"' do
      [2, 3].each do |position|
        described_class.record_result_click(search_type: 'basic', scope: 'blobs', position: position)
      end

      expect(result_clicks_counter).to have_received(:increment).with(
        search_type: 'basic', scope: 'blobs', position_bucket: '2-3'
      ).twice
    end

    it 'buckets positions 4 through 10 as "4-10"' do
      [4, 10].each do |position|
        described_class.record_result_click(search_type: 'basic', scope: 'blobs', position: position)
      end

      expect(result_clicks_counter).to have_received(:increment).with(
        search_type: 'basic', scope: 'blobs', position_bucket: '4-10'
      ).twice
    end

    it 'buckets position 11 and above as "11+"' do
      described_class.record_result_click(search_type: 'basic', scope: 'blobs', position: 11)

      expect(result_clicks_counter).to have_received(:increment).with(
        search_type: 'basic', scope: 'blobs', position_bucket: '11+'
      )
    end

    it 'buckets a nil, zero, negative, or non-numeric position as "11+" rather than raising' do
      [nil, 0, -1, 'not-a-number'].each do |position|
        described_class.record_result_click(search_type: 'basic', scope: 'blobs', position: position)
      end

      expect(result_clicks_counter).to have_received(:increment).with(
        search_type: 'basic', scope: 'blobs', position_bucket: '11+'
      ).exactly(4).times
    end

    it 'clamps an unrecognised scope to nil rather than minting an unbounded series' do
      described_class.record_result_click(search_type: 'basic', scope: 'not-a-real-scope', position: 1)

      expect(result_clicks_counter).to have_received(:increment).with(
        search_type: 'basic', scope: nil, position_bucket: '1'
      )
    end
  end

  describe '.track_event' do
    it 'routes a click_search_result event into record_result_click' do
      expect(described_class).to receive(:record_result_click).with(
        search_type: 'advanced', scope: 'blobs', position: 3
      )

      described_class.track_event('click_search_result', label: 'blobs', value: 3, search_type: 'advanced')
    end

    it 'ignores any other event name' do
      expect(described_class).not_to receive(:record_result_click)

      described_class.track_event('perform_search', label: 'blobs', value: 3, search_type: 'advanced')
    end

    it 'tolerates missing search_type, label, or value' do
      expect(described_class).to receive(:record_result_click).with(
        search_type: nil, scope: nil, position: nil
      )

      described_class.track_event('click_search_result')
    end
  end
end
