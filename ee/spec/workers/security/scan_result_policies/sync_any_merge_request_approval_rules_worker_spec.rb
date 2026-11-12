# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Security::ScanResultPolicies::SyncAnyMergeRequestApprovalRulesWorker, feature_category: :security_policy_management do
  let_it_be(:merge_request) { create(:ee_merge_request) }

  describe 'concurrency limit scope' do
    it 'caps each top-level group at half of the concurrency limit' do
      expect(described_class.get_concurrency_limit_scope).to include(type: :root_namespace, max_percentage: 0.5)
    end

    describe 'enabled lambda' do
      subject(:enabled) { described_class.get_concurrency_limit_scope[:enabled].call }

      it { is_expected.to be(true) }

      context 'when sync_any_merge_request_approval_rules_worker_concurrency_limit_scope is disabled' do
        before do
          stub_feature_flags(sync_any_merge_request_approval_rules_worker_concurrency_limit_scope: false)
        end

        it { is_expected.to be(false) }
      end
    end
  end

  describe '#perform' do
    subject(:run_worker) { described_class.new.perform(merge_request_id) }

    let(:merge_request_id) { merge_request.id }

    it 'calls SyncAnyMergeRequestRulesService' do
      expect_next_instance_of(
        Security::ScanResultPolicies::SyncAnyMergeRequestRulesService,
        merge_request
      ) do |instance|
        expect(instance).to receive(:execute)
      end

      run_worker
    end

    context 'when merge_request does not exist' do
      let(:merge_request_id) { non_existing_record_id }

      it 'does not call SyncAnyMergeRequestRulesService' do
        expect(Security::ScanResultPolicies::SyncAnyMergeRequestRulesService).not_to receive(:new)

        run_worker
      end
    end
  end
end
