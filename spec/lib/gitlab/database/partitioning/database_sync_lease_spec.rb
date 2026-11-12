# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Gitlab::Database::Partitioning::DatabaseSyncLease, :clean_gitlab_redis_shared_state,
  feature_category: :database do
  subject(:sync_lease) { described_class.new('ci') }

  let(:lease_key) { 'gitlab/database/asyncddl/actions/ci' }

  describe '#lease_key' do
    it 'shares the key of the other async DDL actions of the database' do
      expect(sync_lease.lease_key).to eq(lease_key)
    end
  end

  describe '#try_obtain_lease' do
    context 'when another process holds the lease' do
      before do
        Gitlab::ExclusiveLease.new(lease_key, timeout: 1.minute).try_obtain
      end

      it 'logs a warning' do
        expect(Gitlab::AppJsonLogger).to receive(:warn).with(hash_including(lease_key: lease_key))

        sync_lease.try_obtain_lease { :synced }
      end
    end
  end

  describe '#renew' do
    it 'renews the lease without logging a warning' do
      expect(Gitlab::AppJsonLogger).not_to receive(:warn)

      sync_lease.try_obtain_lease { sync_lease.renew }
    end

    context 'when the lease expired or another process took it' do
      it 'logs a warning with the lease key and the database name and does not raise' do
        expect(Gitlab::AppJsonLogger).to receive(:warn).with(hash_including(lease_key: lease_key, database_name: 'ci'))

        expect do
          sync_lease.try_obtain_lease do |uuid|
            Gitlab::ExclusiveLease.cancel(lease_key, uuid)
            sync_lease.renew
          end
        end.not_to raise_error
      end
    end
  end
end
