# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Analytics::DevopsAdoption::CreateSnapshotWorker, feature_category: :devops_reports do
  include ExclusiveLeaseHelpers

  subject(:worker) { described_class.new }

  describe "#perform" do
    let!(:enabled_namespace) { create :devops_adoption_enabled_namespace }

    let!(:pending_snapshot) do
      create(
        :devops_adoption_snapshot,
        namespace: enabled_namespace.namespace,
        end_time: DateTime.parse('2020-10-01').end_of_month,
        recorded_at: DateTime.parse('2020-10-20')
      ).reload
    end

    let!(:finalized_snapshot) do
      create(
        :devops_adoption_snapshot,
        namespace: enabled_namespace.namespace,
        end_time: DateTime.parse('2020-09-01').end_of_month,
        recorded_at: DateTime.parse('2020-10-20')
      ).reload
    end

    it 'updates metrics for all not finalized snapshots and previous month' do
      freeze_time do
        allow_next_instance_of(Analytics::DevopsAdoption::Snapshots::CalculateAndSaveService, enabled_namespace: enabled_namespace, range_end: pending_snapshot.end_time) do |instance|
          expect(instance).to receive(:execute)
        end
        allow_next_instance_of(Analytics::DevopsAdoption::Snapshots::CalculateAndSaveService, enabled_namespace: enabled_namespace, range_end: finalized_snapshot.end_time) do |instance|
          expect(instance).not_to receive(:execute)
        end
        allow_next_instance_of(Analytics::DevopsAdoption::Snapshots::CalculateAndSaveService, enabled_namespace: enabled_namespace, range_end: (Time.zone.now - 1.month).end_of_month) do |instance|
          expect(instance).to receive(:execute)
        end

        worker.perform(enabled_namespace.id)
      end
    end

    context 'when pending metric for previous month already exists' do
      it 'calls for previous month calculation only once' do
        travel_to(pending_snapshot.recorded_at + 1.month) do
          allow_next_instance_of(Analytics::DevopsAdoption::Snapshots::CalculateAndSaveService, enabled_namespace: enabled_namespace, range_end: pending_snapshot.end_time) do |instance|
            expect(instance).to receive(:execute).once
          end
          allow_next_instance_of(Analytics::DevopsAdoption::Snapshots::CalculateAndSaveService, enabled_namespace: enabled_namespace, range_end: finalized_snapshot.end_time) do |instance|
            expect(instance).not_to receive(:execute)
          end

          worker.perform(enabled_namespace.id)
        end
      end
    end

    context 'when metric for previous month already finalized' do
      it 'does not call for previous month calculation' do
        travel_to(finalized_snapshot.recorded_at + 1.month) do
          allow_next_instance_of(Analytics::DevopsAdoption::Snapshots::CalculateAndSaveService) do |instance|
            allow(instance).to receive(:execute).and_call_original
          end
          allow_next_instance_of(Analytics::DevopsAdoption::Snapshots::CalculateAndSaveService, enabled_namespace: enabled_namespace, range_end: finalized_snapshot.end_time) do |instance|
            expect(instance).not_to receive(:execute)
          end

          worker.perform(enabled_namespace.id)
        end
      end
    end

    it_behaves_like 'an idempotent worker' do
      let(:job_args) { enabled_namespace.id }
    end

    it 'takes a lease for the namespace and renews it before each range', :aggregate_failures do
      lease = stub_exclusive_lease(
        "analytics/devops_adoption/create_snapshot_worker:#{enabled_namespace.namespace_id}",
        timeout: described_class::LEASE_TTL
      )
      expect(lease).to receive(:try_obtain)
      expect(lease).to receive(:renew).twice
      allow_next_instances_of(Analytics::DevopsAdoption::Snapshots::CalculateAndSaveService, 2) do |instance|
        expect(instance).to receive(:execute)
      end

      worker.perform(enabled_namespace.id)
    end

    context 'when another job holds the lease for the namespace' do
      before do
        stub_exclusive_lease_taken(
          "analytics/devops_adoption/create_snapshot_worker:#{enabled_namespace.namespace_id}",
          timeout: described_class::LEASE_TTL
        )
      end

      it 'skips the calculation and records the result' do
        expect(Analytics::DevopsAdoption::Snapshots::CalculateAndSaveService).not_to receive(:new)
        expect(worker).to receive(:log_extra_metadata_on_done).with(:result, :skipped)

        worker.perform(enabled_namespace.id)
      end

      context 'when the devops_adoption_enabled_namespaces_cap feature flag is disabled' do
        before do
          stub_feature_flags(devops_adoption_enabled_namespaces_cap: false)
        end

        it 'calculates without taking the lease' do
          expect(Gitlab::ExclusiveLease).not_to receive(:new)
          expect(worker).not_to receive(:log_extra_metadata_on_done)
          allow_next_instances_of(Analytics::DevopsAdoption::Snapshots::CalculateAndSaveService, 2) do |instance|
            expect(instance).to receive(:execute)
          end

          worker.perform(enabled_namespace.id)
        end
      end
    end
  end
end
