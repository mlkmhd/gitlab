# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Gitlab::Metrics::GlobalSearchSlis, feature_category: :global_search do
  using RSpec::Parameterized::TableSyntax

  describe '#initialize_slis!' do
    let(:api_endpoint_labels) do
      [a_hash_including(endpoint_id: 'GET /api/:version/search')]
    end

    let(:web_endpoint_labels) do
      [
        a_hash_including(endpoint_id: "SearchController#show"),
        a_hash_including(endpoint_id: "SearchController#count"),
        a_hash_including(endpoint_id: "SearchController#autocomplete")
      ]
    end

    let(:all_endpoint_labels) do
      api_endpoint_labels + web_endpoint_labels
    end

    it 'initializes Apdex SLIs for global_search' do
      expect(Gitlab::Metrics::Sli::Apdex).to receive(:initialize_sli).with(
        :global_search,
        array_including(all_endpoint_labels)
      )

      described_class.initialize_slis!
    end

    it 'initializes ErrorRate SLIs for global_search' do
      expect(Gitlab::Metrics::Sli::ErrorRate).to receive(:initialize_sli).with(
        :global_search,
        array_including(all_endpoint_labels)
      )

      described_class.initialize_slis!
    end

    where(:search_type, :search_scope, :search_level, :valid) do
      'basic' | 'work_items' | 'global'  | true
      'basic' | 'blobs'      | 'project' | true
      'basic' | 'blobs'      | 'global'  | false
      'basic' | 'blobs'      | 'group'   | false
      'basic' | 'wiki_blobs' | 'global'  | false
      'basic' | 'commits'    | 'global'  | false
    end

    with_them do
      it 'initializes valid label combinations and excludes impossible ones' do
        if valid
          expect(Gitlab::Metrics::Sli::Apdex).to receive(:initialize_sli).with(
            :global_search, array_including(a_hash_including(
              search_type: search_type, search_scope: search_scope, search_level: search_level
            ))
          )
        else
          expect(Gitlab::Metrics::Sli::Apdex).not_to receive(:initialize_sli).with(
            :global_search, array_including(a_hash_including(
              search_type: search_type, search_scope: search_scope, search_level: search_level
            ))
          )
        end

        described_class.initialize_slis!
      end
    end

    context 'when initializing autocomplete labels' do
      before do
        allow(Gitlab::Metrics::Environment).to receive_messages(web?: true, api?: false)
      end

      it 'registers autocomplete as a single label combination' do
        expect(Gitlab::Metrics::Sli::Apdex).to receive(:initialize_sli).with(
          :global_search, array_including(a_hash_including(
            endpoint_id: 'SearchController#autocomplete',
            search_type: nil,
            search_level: nil,
            search_scope: nil
          ))
        )

        described_class.initialize_slis!
      end

      it 'registers autocomplete error rate as a single label combination' do
        expect(Gitlab::Metrics::Sli::ErrorRate).to receive(:initialize_sli).with(
          :global_search, array_including(a_hash_including(
            endpoint_id: 'SearchController#autocomplete',
            search_type: nil,
            search_level: nil,
            search_scope: nil
          ))
        )

        described_class.initialize_slis!
      end
    end

    context 'when initializing search types', unless: Gitlab.ee? do
      it 'does not include zoekt search type' do
        expect(Gitlab::Metrics::Sli::Apdex).not_to receive(:initialize_sli).with(
          :global_search, array_including(a_hash_including(search_type: 'zoekt'))
        )

        described_class.initialize_slis!
      end

      it 'does not include advanced search type' do
        expect(Gitlab::Metrics::Sli::Apdex).not_to receive(:initialize_sli).with(
          :global_search, array_including(a_hash_including(search_type: 'advanced'))
        )

        described_class.initialize_slis!
      end
    end

    context "when initializing for limited types" do
      where(:api, :web) do
        [true, false].repeated_permutation(2).to_a
      end

      with_them do
        it 'only initializes for the relevant endpoints', :aggregate_failures do
          allow(Gitlab::Metrics::Environment).to receive_messages(api?: api, web?: web)
          allow(Gitlab::Metrics::Sli::Apdex).to receive(:initialize_sli)
          allow(Gitlab::Metrics::Sli::ErrorRate).to receive(:initialize_sli)

          described_class.initialize_slis!

          if api
            expect(Gitlab::Metrics::Sli::Apdex).to(
              have_received(:initialize_sli).with(:global_search, array_including(*api_endpoint_labels))
            )
            expect(Gitlab::Metrics::Sli::ErrorRate).to(
              have_received(:initialize_sli).with(:global_search, array_including(*api_endpoint_labels))
            )
          else
            expect(Gitlab::Metrics::Sli::Apdex).not_to(
              have_received(:initialize_sli).with(:global_search, array_including(*api_endpoint_labels))
            )
            expect(Gitlab::Metrics::Sli::ErrorRate).not_to(
              have_received(:initialize_sli).with(:global_search, array_including(*api_endpoint_labels))
            )
          end

          if web
            expect(Gitlab::Metrics::Sli::Apdex).to(
              have_received(:initialize_sli).with(:global_search, array_including(*web_endpoint_labels))
            )
            expect(Gitlab::Metrics::Sli::ErrorRate).to(
              have_received(:initialize_sli).with(:global_search, array_including(*web_endpoint_labels))
            )
          else
            expect(Gitlab::Metrics::Sli::Apdex).not_to(
              have_received(:initialize_sli).with(:global_search, array_including(*web_endpoint_labels))
            )
            expect(Gitlab::Metrics::Sli::ErrorRate).not_to(
              have_received(:initialize_sli).with(:global_search, array_including(*web_endpoint_labels))
            )
          end
        end
      end
    end
  end

  describe '#record_apdex' do
    let(:duration_histogram) { instance_double(Prometheus::Client::Histogram, observe: nil) }

    before do
      allow(::Gitlab::ApplicationContext).to receive(:current_context_attribute).with(:caller_id).and_return('end')
      allow(Gitlab::AppJsonLogger).to receive(:info)

      described_class.clear_memoization(:duration_histogram)
      allow(Gitlab::Metrics).to receive(:histogram).and_call_original
      allow(Gitlab::Metrics).to receive(:histogram)
        .with(:gitlab_global_search_duration_seconds, anything, anything, anything)
        .and_return(duration_histogram)
    end

    after do
      described_class.clear_memoization(:duration_histogram)
    end

    where(:search_type, :code_search, :duration_target) do
      'basic'    | false | 8.812
      'basic'    | true  | 27.538
      'advanced' | false | 2.452
      'advanced' | true  | 15.52
      'zoekt'    | true  | 15.52
      'unknown'  | false | 5
      nil        | false | 5
    end

    with_them do
      let(:search_scope) { code_search ? 'blobs' : 'work_items' }

      it 'increments the global_search SLI as a success if the elapsed time is within the target' do
        duration = duration_target - 0.1

        expect(Gitlab::Metrics::Sli::Apdex[:global_search]).to receive(:increment).with(
          labels: {
            search_type: search_type,
            search_level: 'global',
            search_scope: search_scope,
            endpoint_id: 'end'
          },
          success: true
        )

        expect(Gitlab::AppJsonLogger).to receive(:info).with(
          message: "Global Search Apdex SLI",
          duration_s: duration,
          target_s: duration_target,
          success: true,
          search_type: search_type,
          search_level: 'global',
          search_scope: search_scope
        )

        described_class.record_apdex(
          elapsed: duration,
          search_type: search_type,
          search_level: 'global',
          search_scope: search_scope
        )
      end

      it 'increments the global_search SLI as a failure if the elapsed time is not within the target' do
        duration = duration_target + 0.1

        expect(Gitlab::Metrics::Sli::Apdex[:global_search]).to receive(:increment).with(
          labels: {
            search_type: search_type,
            search_level: 'global',
            search_scope: search_scope,
            endpoint_id: 'end'
          },
          success: false
        )

        expect(Gitlab::AppJsonLogger).to receive(:info).with(
          message: "Global Search Apdex SLI",
          duration_s: duration,
          target_s: duration_target,
          success: false,
          search_type: search_type,
          search_level: 'global',
          search_scope: search_scope
        )

        described_class.record_apdex(
          elapsed: duration,
          search_type: search_type,
          search_level: 'global',
          search_scope: search_scope
        )
      end
    end

    context 'when the search scope is merge_requests and the search type is basic' do
      it 'increments the global_search SLI as a success if the elapsed time is within the target' do
        expect(Gitlab::Metrics::Sli::Apdex[:global_search]).to receive(:increment).with(
          labels: {
            search_type: 'basic',
            search_level: 'global',
            search_scope: 'merge_requests',
            endpoint_id: 'end'
          },
          success: true
        )

        expect(Gitlab::AppJsonLogger).to receive(:info).with(
          message: "Global Search Apdex SLI",
          duration_s: 14,
          target_s: 15,
          success: true,
          search_type: 'basic',
          search_level: 'global',
          search_scope: 'merge_requests'
        )

        described_class.record_apdex(
          elapsed: 14,
          search_type: 'basic',
          search_level: 'global',
          search_scope: 'merge_requests'
        )
      end

      it 'increments the global_search SLI as a failure if the elapsed time is not within the target' do
        expect(Gitlab::Metrics::Sli::Apdex[:global_search]).to receive(:increment).with(
          labels: {
            search_type: 'basic',
            search_level: 'global',
            search_scope: 'merge_requests',
            endpoint_id: 'end'
          },
          success: false
        )

        described_class.record_apdex(
          elapsed: 16,
          search_type: 'basic',
          search_level: 'global',
          search_scope: 'merge_requests'
        )
      end
    end

    describe 'DURATION_BUCKETS' do
      it 'matches the literal edges, so a future edit must touch this spec' do
        expect(described_class::DURATION_BUCKETS)
          .to eq([0.025, 0.05, 0.1, 0.25, 0.5, 1, 2.5, 5, 10, 15, 20, 30, 45, 60])
      end

      it 'resolves below 100ms, so autocomplete and fast scopes have a computable p50' do
        expect(described_class::DURATION_BUCKETS.count { |edge| edge < 0.1 }).to be >= 2
      end

      it 'is strictly ascending, as the Prometheus client requires' do
        expect(described_class::DURATION_BUCKETS).to eq(described_class::DURATION_BUCKETS.uniq.sort)
      end
    end

    context 'with the search duration histogram' do
      it 'registers the histogram with DURATION_BUCKETS' do
        described_class.record_apdex(
          elapsed: 1.5,
          search_type: 'advanced',
          search_level: 'global',
          search_scope: 'work_items'
        )

        expect(Gitlab::Metrics).to have_received(:histogram).with(
          :gitlab_global_search_duration_seconds,
          an_instance_of(String),
          {},
          described_class::DURATION_BUCKETS
        )
      end

      it 'observes the elapsed time labelled by search type, level and scope' do
        described_class.record_apdex(
          elapsed: 3.25,
          search_type: 'basic',
          search_level: 'group',
          search_scope: 'users'
        )

        expect(duration_histogram).to have_received(:observe).with(
          { search_type: 'basic', search_level: 'group', search_scope: 'users' },
          3.25
        )
      end

      it 'observes autocomplete requests with nil labels' do
        described_class.record_apdex(
          elapsed: 0.05,
          search_type: nil,
          search_level: nil,
          search_scope: nil
        )

        expect(duration_histogram).to have_received(:observe).with(
          { search_type: nil, search_level: nil, search_scope: nil },
          0.05
        )
      end

      it 'registers the histogram once across requests' do
        2.times do
          described_class.record_apdex(
            elapsed: 1,
            search_type: 'basic',
            search_level: 'project',
            search_scope: 'blobs'
          )
        end

        expect(Gitlab::Metrics).to have_received(:histogram)
          .with(:gitlab_global_search_duration_seconds, anything, anything, anything).once
        expect(duration_histogram).to have_received(:observe).twice
      end

      it 'skips the histogram observation when observe_duration is false' do
        described_class.record_apdex(
          elapsed: 1,
          search_type: 'basic',
          search_level: 'global',
          search_scope: 'issues',
          observe_duration: false
        )

        expect(duration_histogram).not_to have_received(:observe)
      end

      context 'when global_search_duration_histogram is disabled' do
        before do
          stub_feature_flags(global_search_duration_histogram: false)
        end

        it 'skips the histogram observation' do
          described_class.record_apdex(
            elapsed: 1,
            search_type: 'basic',
            search_level: 'global',
            search_scope: 'issues'
          )

          expect(duration_histogram).not_to have_received(:observe)
        end
      end
    end

    context 'when the endpoint is autocomplete' do
      before do
        allow(::Gitlab::ApplicationContext).to receive(:current_context_attribute)
          .with(:caller_id).and_return('SearchController#autocomplete')
      end

      # Discriminating on purpose: AUTOCOMPLETE_TARGET_S and DEFAULT_TARGET_S are
      # both 5, so a nil-dimension example would pass even without the branch.
      # These dimensions would resolve to ADVANCED_CODE_TARGET_S (15.52).
      it 'scores against the autocomplete target and not the search_type branches' do
        allow(Gitlab::Metrics::Sli::Apdex[:global_search]).to receive(:increment)
        expect(Gitlab::AppJsonLogger).to receive(:info).with(a_hash_including(target_s: 5))

        described_class.record_apdex(
          elapsed: 4.9,
          search_type: 'advanced',
          search_level: 'global',
          search_scope: 'blobs'
        )
      end
    end
  end

  describe '#record_apdex with the real Prometheus client', :prometheus do
    before do
      allow(::Gitlab::ApplicationContext).to receive(:current_context_attribute).with(:caller_id).and_return('end')
      allow(Gitlab::AppJsonLogger).to receive(:info)

      described_class.clear_memoization(:duration_histogram)
    end

    after do
      described_class.clear_memoization(:duration_histogram)
    end

    def observe(search_type:, search_level:, search_scope:, elapsed: 1)
      described_class.record_apdex(
        elapsed: elapsed,
        search_type: search_type,
        search_level: search_level,
        search_scope: search_scope
      )
    end

    it 'registers the histogram and keeps nil and non-nil label sets as distinct series' do
      observe(search_type: 'basic', search_level: 'global', search_scope: 'work_items', elapsed: 3.25)
      observe(search_type: nil, search_level: nil, search_scope: nil, elapsed: 0.05)

      histogram = ::Prometheus::Client.registry.get(:gitlab_global_search_duration_seconds)

      expect(histogram).not_to be_nil
      expect(histogram.get(search_type: 'basic', search_level: 'global', search_scope: 'work_items')[5]).to eq(1)
      expect(histogram.get(search_type: nil, search_level: nil, search_scope: nil)[0.1]).to eq(1)
    end
  end

  describe '#derived_duration_target' do
    # A scope or search type added later that derives no target fails here, rather
    # than being silently scored against the un-derived DEFAULT_TARGET_S. Nil is
    # the signal, not the value: the fallthrough and two chosen targets are all 5.
    it 'derives a target for every registered label combination' do
      labels = described_class.send(:possible_labels)
      expect(labels).not_to be_empty # or the select below passes vacuously

      fallthrough = labels.select do |label|
        described_class.send(:derived_duration_target, label[:search_type], label[:search_scope]).nil?
      end

      expect(fallthrough).to be_empty
    end

    it 'derives nothing for a combination no branch claims' do
      expect(described_class.send(:derived_duration_target, 'no-such-type', 'blobs')).to be_nil
    end
  end

  describe '#record_error_rate' do
    before do
      allow(::Gitlab::ApplicationContext).to receive(:current_context_attribute).with(:caller_id).and_return('end')
      allow(Gitlab::AppJsonLogger).to receive(:info)
    end

    it 'calls increment on the error rate SLI and logs the error' do
      expect(Gitlab::Metrics::Sli::ErrorRate[:global_search]).to receive(:increment)

      expect(Gitlab::AppJsonLogger).to receive(:info).with(
        message: "Global Search Error Rate SLI",
        error: true,
        search_type: 'basic',
        search_level: 'global',
        search_scope: 'work_items'
      )

      described_class.record_error_rate(
        error: true,
        search_type: 'basic',
        search_level: 'global',
        search_scope: 'work_items'
      )
    end
  end

  describe '.search_scopes' do
    it 'returns all scope names from Search::Scopes' do
      result = described_class.send(:search_scopes)
      expect(result).to eq(::Search::Scopes.all_scope_names)
    end

    it 'includes expected scopes' do
      result = described_class.send(:search_scopes)
      expect(result).to include('blobs', 'merge_requests', 'projects', 'work_items')
    end
  end
end
