# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Ci::LowUrgencyCancelRedundantPipelinesWorker, feature_category: :continuous_integration do
  it 'is labeled as low urgency' do
    expect(described_class.get_urgency).to eq(:low)
  end

  it_behaves_like 'a worker with a concurrency limit scope',
    type: :root_namespace, max_percentage: 0.4, feature_flag: :ci_pipeline_execution_concurrency_limit_scope_wave_two
end
