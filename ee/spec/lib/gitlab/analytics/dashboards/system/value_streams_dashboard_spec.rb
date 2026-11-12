# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'Value Streams Dashboard system dashboard', feature_category: :value_stream_management do
  let(:dashboard) { Analytics::CustomDashboards::SystemDashboardsLoader.find_by_slug('value_streams_dashboard') }
  let(:panels) { dashboard.config['panels'] }

  it 'passes schema validation' do
    expect(dashboard.errors).to be_empty
  end

  it 'reads every panel from the legacy data sources' do
    expect(panels.map { |panel| panel.dig('visualization', 'data', 'type') }.uniq)
      .to match_array(%w[namespace_metadata usage_count value_stream dora_metrics_by_project])
  end

  it 'hides the date range filter, because no panel reads it' do
    expect(dashboard.config.dig('filters', 'dateRange', 'enabled')).to be(false)
  end
end
