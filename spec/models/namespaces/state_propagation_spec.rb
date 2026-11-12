# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Namespaces::StatePropagation, feature_category: :groups_and_projects do
  let_it_be(:namespace) { create(:namespace) }

  describe 'associations' do
    it { is_expected.to belong_to(:namespace).required }
  end

  describe 'validations' do
    subject { build(:namespace_state_propagation) }

    it { is_expected.to validate_presence_of(:source_state) }
    it { is_expected.to validate_presence_of(:target_state) }
    it { is_expected.to validate_presence_of(:status) }
  end

  describe 'enums' do
    it 'defines status enum' do
      expect(described_class.statuses).to eq({ 'pending' => 0, 'processing' => 1 })
    end

    it 'defines source_state enum' do
      expect(described_class.source_states).to eq({
        'ancestor_inherited' => 0,
        'archived' => 1,
        'deletion_scheduled' => 2,
        'creation_in_progress' => 3,
        'deletion_in_progress' => 4,
        'transfer_in_progress' => 5,
        'maintenance' => 6,
        'transfer_scheduled' => 7
      })
    end

    it 'defines target_state enum' do
      expect(described_class.target_states).to eq({
        'ancestor_inherited' => 0,
        'archived' => 1,
        'deletion_scheduled' => 2,
        'creation_in_progress' => 3,
        'deletion_in_progress' => 4,
        'transfer_in_progress' => 5,
        'maintenance' => 6,
        'transfer_scheduled' => 7
      })
    end
  end

  describe 'scopes' do
    let_it_be(:pending_propagation) do
      create(:namespace_state_propagation, :pending, namespace: namespace, target_state: :archived)
    end

    let_it_be(:processing_propagation) do
      create(:namespace_state_propagation, :processing, namespace: namespace, target_state: :deletion_scheduled)
    end

    describe '.pending' do
      it 'returns only pending propagations' do
        expect(described_class.pending).to contain_exactly(pending_propagation)
      end
    end

    describe '.processing' do
      it 'returns only processing propagations' do
        expect(described_class.processing).to contain_exactly(processing_propagation)
      end
    end

    describe '.order_by_created_at_asc' do
      it 'orders by created_at ascending' do
        oldest = create(:namespace_state_propagation, namespace: create(:namespace), created_at: 2.days.ago)
        newest = create(:namespace_state_propagation, namespace: create(:namespace), created_at: 1.day.from_now)

        ids = described_class.where(id: [oldest.id, pending_propagation.id,
          newest.id]).order_by_created_at_asc.pluck(:id)

        expect(ids).to eq([oldest.id, pending_propagation.id, newest.id])
      end
    end

    describe '.stuck_processing' do
      let_it_be(:stale_processing) do
        create(:namespace_state_propagation, :processing, namespace: create(:namespace), started_at: 2.hours.ago)
      end

      let_it_be(:stale_pending) do
        create(:namespace_state_propagation, namespace: create(:namespace), started_at: 2.hours.ago)
      end

      it 'returns only processing records started at or before the threshold' do
        expect(described_class.stuck_processing(1.hour.ago)).to contain_exactly(stale_processing)
      end
    end

    describe '.stale_pending' do
      let_it_be(:stale_pending) do
        create(:namespace_state_propagation, namespace: create(:namespace), created_at: 2.hours.ago)
      end

      let_it_be(:stale_processing) do
        create(:namespace_state_propagation, :processing, namespace: create(:namespace), created_at: 2.hours.ago)
      end

      let_it_be(:young_pending) do
        create(:namespace_state_propagation, namespace: create(:namespace), created_at: 30.minutes.ago)
      end

      it 'returns only pending records created at or before the threshold' do
        expect(described_class.stale_pending(1.hour.ago)).to contain_exactly(stale_pending)
      end
    end

    describe '.with_namespace_route' do
      it 'preloads the namespace route' do
        record = described_class.where(id: pending_propagation.id).with_namespace_route.first

        expect(record.association(:namespace)).to be_loaded
        expect(record.namespace.association(:route)).to be_loaded
      end
    end

    describe '.counts_by_status' do
      it 'returns the record count keyed by status name' do
        expect(described_class.counts_by_status).to eq({ 'pending' => 1, 'processing' => 1 })
      end
    end
  end

  describe '.next_for' do
    it 'returns the oldest record for the namespace, whatever its status' do
      oldest = create(:namespace_state_propagation, :processing, namespace: namespace)
      create(:namespace_state_propagation, :archived_to_ancestor_inherited, namespace: namespace)
      create(:namespace_state_propagation, namespace: create(:namespace))

      expect(described_class.next_for(namespace.id)).to eq(oldest)
    end

    it 'returns nil when the namespace has no records' do
      expect(described_class.next_for(namespace.id)).to be_nil
    end
  end

  describe '#claim' do
    let!(:propagation) { create(:namespace_state_propagation, :pending, namespace: namespace) }

    it 'marks a pending record as processing and returns true', :freeze_time, :aggregate_failures do
      expect(propagation.claim).to be(true)

      propagation.reload
      expect(propagation).to be_status_processing
      expect(propagation.started_at).to eq(Time.current)
    end

    it 'returns false when the record was already claimed' do
      described_class.find(propagation.id).claim

      expect(propagation.claim).to be(false)
    end
  end

  describe '#release' do
    let!(:propagation) { create(:namespace_state_propagation, :pending, namespace: namespace) }

    it 'returns a claimed record to pending so it can be claimed again', :aggregate_failures do
      propagation.claim

      propagation.release

      propagation.reload
      expect(propagation).to be_status_pending
      expect(propagation.started_at).to be_nil
      expect(propagation.claim).to be(true)
    end
  end

  describe 'unique constraint' do
    it 'allows several pending records for the same namespace and target_state' do
      create(:namespace_state_propagation, namespace: namespace, target_state: :archived, status: :pending)

      duplicate = build(:namespace_state_propagation, namespace: namespace, target_state: :archived, status: :pending)

      expect { duplicate.save! }.not_to raise_error
    end

    it 'prevents a second processing record for the same namespace' do
      create(:namespace_state_propagation, namespace: namespace, target_state: :archived, status: :processing)

      other = build(:namespace_state_propagation, namespace: namespace, target_state: :deletion_scheduled,
        status: :processing)

      expect { other.save! }.to raise_error(ActiveRecord::RecordNotUnique)
    end

    it 'allows processing records for different namespaces' do
      create(:namespace_state_propagation, namespace: namespace, status: :processing)

      other = build(:namespace_state_propagation, namespace: create(:namespace), status: :processing)

      expect { other.save! }.not_to raise_error
    end
  end

  describe 'cascade deletion' do
    it 'deletes propagation records when namespace is deleted', :aggregate_failures do
      propagation = create(:namespace_state_propagation, namespace: namespace)

      expect { namespace.destroy! }.to change { described_class.count }.by(-1)
      expect(described_class.find_by(id: propagation.id)).to be_nil
    end
  end
end
