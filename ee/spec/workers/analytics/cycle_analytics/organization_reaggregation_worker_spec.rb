# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Analytics::CycleAnalytics::OrganizationReaggregationWorker, feature_category: :value_stream_management do
  let_it_be(:organization) { create(:common_organization) }

  it { expect(described_class.get_concurrency_limit).to eq(10) }
  it { expect(described_class.get_deduplicate_strategy).to eq(:until_executed) }

  it_behaves_like 'aggregator worker examples' do
    let(:expected_mode) { :full }
    let(:worker_args) { [organization.id] }
  end

  context 'with aggregations in two organizations' do
    let_it_be(:other_organization) { create(:organization) }
    let_it_be(:aggregation) do
      create(:cycle_analytics_aggregation, namespace: create(:group, organization: organization))
    end

    let_it_be(:other_aggregation) do
      create(:cycle_analytics_aggregation, namespace: create(:group, organization: other_organization))
    end

    before do
      stub_licensed_features(cycle_analytics_for_groups: true)
    end

    it 'aggregates only the given organization' do
      described_class.new.perform(organization.id)

      expect(aggregation.reload.last_full_run_at).to be_present
      expect(other_aggregation.reload.last_full_run_at).to be_nil
    end

    context 'when the organization does not exist' do
      it 'does nothing' do
        expect(Analytics::CycleAnalytics::NamespaceAggregatorService).not_to receive(:new)

        described_class.new.perform(non_existing_record_id)
      end
    end

    context 'without an organization' do
      it 'aggregates every organization' do
        described_class.new.perform(nil)

        expect(aggregation.reload.last_full_run_at).to be_present
        expect(other_aggregation.reload.last_full_run_at).to be_present
      end
    end
  end
end
