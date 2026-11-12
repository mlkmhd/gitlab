# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Analytics::CycleAnalytics::IncrementalWorker, feature_category: :value_stream_management do
  let_it_be(:organization) { create(:organization) }
  let_it_be(:other_organization) { create(:organization) }
  let_it_be(:aggregation) do
    create(:cycle_analytics_aggregation, namespace: create(:group, organization: organization))
  end

  let_it_be(:other_aggregation) do
    create(:cycle_analytics_aggregation, namespace: create(:group, organization: other_organization))
  end

  subject(:worker) { described_class.new }

  it_behaves_like 'an idempotent worker'

  it 'schedules one job per organization, in its organization context' do
    create(:organization)

    Sidekiq::Testing.fake! { worker.perform }

    jobs = Analytics::CycleAnalytics::OrganizationIncrementalWorker.jobs.map do |job|
      job.values_at('args', 'meta.organization_id')
    end

    expect(jobs).to match_array(Organizations::Organization.pluck(:id).map { |id| [[id], id] })
  end

  context 'when vsa_aggregation_per_organization is disabled' do
    before do
      stub_feature_flags(vsa_aggregation_per_organization: false)
      stub_licensed_features(cycle_analytics_for_groups: true)
    end

    it 'aggregates every organization without scheduling jobs' do
      Sidekiq::Testing.fake! { worker.perform }

      expect(Analytics::CycleAnalytics::OrganizationIncrementalWorker.jobs).to be_empty
      expect(aggregation.reload.last_incremental_run_at).to be_present
      expect(other_aggregation.reload.last_incremental_run_at).to be_present
    end
  end
end
