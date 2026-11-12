# frozen_string_literal: true

require 'fast_spec_helper'
require 'gitlab/safe_request_store'
require 'gitlab/rspec/all'

RSpec.describe Gitlab::Metrics::GlqlSlis, feature_category: :glql do
  def glql_labels(endpoint_id, error_type, client)
    {
      endpoint_id: endpoint_id,
      feature_category: 'glql',
      query_urgency: :low,
      error_type: error_type,
      client: client
    }
  end

  describe '.initialize_slis!' do
    include StubENV

    where(:fleet, :endpoint_clients) do
      ui_other = ['Glql::BaseController#execute', 'other']
      api_other = ['POST /api/:version/glql', 'other']
      api_duo_agent = ['POST /api/:version/glql', 'duo_agent']

      [
        ['api', [ui_other, api_other]],
        ['ai-assisted', [api_duo_agent]],
        ['web', []],
        [nil, [ui_other, api_other, api_duo_agent]]
      ]
    end

    with_them do
      before do
        allow(Gitlab::Metrics::Sli::Apdex).to receive(:initialize_sli)
        allow(Gitlab::Metrics::Sli::ErrorRate).to receive(:initialize_sli)
        stub_env('GITLAB_METRICS_INITIALIZE', fleet)

        described_class.initialize_slis!
      end

      it 'initializes Apdex SLIs with the labels of queries that did not fail' do
        expect(Gitlab::Metrics::Sli::Apdex).to have_received(:initialize_sli).with(
          :glql,
          match_array(endpoint_clients.map { |endpoint_id, client| glql_labels(endpoint_id, nil, client) })
        )
      end

      it 'initializes ErrorRate SLIs with every error type' do
        expected_labels = endpoint_clients.product([:query_aborted, :other, nil]).map do |(endpoint_id, client), type|
          glql_labels(endpoint_id, type, client)
        end

        expect(Gitlab::Metrics::Sli::ErrorRate).to have_received(:initialize_sli).with(
          :glql,
          match_array(expected_labels)
        )
      end
    end
  end

  describe '.labels' do
    using RSpec::Parameterized::TableSyntax

    where(:duo_agent, :client) do
      true  | 'duo_agent'
      false | 'other'
    end

    with_them do
      it 'returns the labels the SLIs are initialized with' do
        expect(described_class.labels(endpoint_id: 'POST /api/:version/glql', error_type: :other, duo_agent: duo_agent))
          .to eq(glql_labels('POST /api/:version/glql', :other, client))
      end
    end
  end

  describe '.record_apdex' do
    it 'calls increment on success SLI' do
      expect(Gitlab::Metrics::Sli::Apdex[:glql]).to receive(:increment).with(
        labels: { feature_category: :foo },
        success: true
      )

      described_class.record_apdex(labels: { feature_category: :foo }, success: true)
    end
  end

  describe '.record_error' do
    it 'calls increment on the error rate SLI' do
      expect(Gitlab::Metrics::Sli::ErrorRate[:glql]).to receive(:increment)

      described_class.record_error(labels: { feature_category: :foo }, error: true)
    end
  end
end
