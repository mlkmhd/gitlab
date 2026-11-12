# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'Merge request analytics system dashboard', feature_category: :value_stream_management do
  let(:dashboard) { Analytics::CustomDashboards::SystemDashboardsLoader.find_by_slug('merge_request_analytics') }
  let(:panels) { dashboard.config['panels'] }

  it 'passes schema validation' do
    expect(dashboard.errors).to be_empty
  end

  describe 'the GLQL panels' do
    using RSpec::Parameterized::TableSyntax

    where(:title, :display, :metrics) do
      'Mean time to merge' | 'stat'      | 'timeToMergeMean'
      'Throughput'         | 'areaChart' | 'throughputCount as "Merge requests merged"'
    end

    with_them do
      let(:data) { panels.find { |panel| panel['title'] == title }.dig('visualization', 'data') }

      it 'queries merge requests by merge date', :aggregate_failures do
        glql = YAML.safe_load(data.dig('query', 'glql'))

        expect(data.dig('query', 'dateField')).to eq('merged')
        expect(glql).to include(
          'display' => display,
          'mode' => 'analytics',
          'query' => 'type = MergeRequest',
          'metrics' => metrics
        )
      end
    end
  end
end
