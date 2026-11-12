# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Analytics::CycleAnalytics::ConsistencyWorker, feature_category: :value_stream_management do
  let_it_be(:organization) { create(:organization) }
  let_it_be(:other_organization) { create(:organization) }

  subject(:worker) { described_class.new }

  it_behaves_like 'an idempotent worker'

  it 'schedules one job per organization, in its organization context' do
    create(:organization)

    Sidekiq::Testing.fake! { worker.perform }

    jobs = Analytics::CycleAnalytics::OrganizationConsistencyWorker.jobs.map do |job|
      job.values_at('args', 'meta.organization_id')
    end

    expect(jobs).to match_array(Organizations::Organization.pluck(:id).map { |id| [[id], id] })
  end

  context 'when vsa_aggregation_per_organization is disabled' do
    let_it_be(:aggregation) do
      create(:cycle_analytics_aggregation, last_consistency_check_updated_at: 10.minutes.ago,
        namespace: create(:group, organization: organization))
    end

    let_it_be(:other_aggregation) do
      create(:cycle_analytics_aggregation, last_consistency_check_updated_at: 10.minutes.ago,
        namespace: create(:group, organization: other_organization))
    end

    before do
      stub_feature_flags(vsa_aggregation_per_organization: false)
    end

    it 'checks every organization without scheduling jobs' do
      freeze_time do
        Sidekiq::Testing.fake! { worker.perform }

        expect(Analytics::CycleAnalytics::OrganizationConsistencyWorker.jobs).to be_empty
        expect(aggregation.reload.last_consistency_check_updated_at).to eq(Time.current)
        expect(other_aggregation.reload.last_consistency_check_updated_at).to eq(Time.current)
      end
    end
  end
end
