# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Observability::ErrorTrackingReactiveCachingWorker, feature_category: :observability do
  it_behaves_like 'reactive cacheable worker'

  it 'keeps the external dependency worker attributes' do
    expect(described_class.worker_has_external_dependencies?).to be(true)
    expect(described_class.get_worker_resource_boundary).to eq(:cpu)
    expect(described_class.get_data_consistency_per_database).to include({ main: :sticky })
    expect(described_class.get_feature_category).to eq(:observability)
  end

  it 'limits concurrent jobs' do
    expect(described_class.get_concurrency_limit).to eq(described_class::CONCURRENCY_LIMIT)
  end
end
