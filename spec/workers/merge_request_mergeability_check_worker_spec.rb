# frozen_string_literal: true

require 'spec_helper'

RSpec.describe MergeRequestMergeabilityCheckWorker, feature_category: :code_review_workflow do
  subject { described_class.new }

  describe 'concurrency limit scope' do
    let(:scope) { Gitlab::SidekiqMiddleware::ConcurrencyLimit::Scope.for(described_class) }

    before do
      stub_feature_flags("disable_sidekiq_concurrency_limit_scope_#{described_class.name}": false)
    end

    it 'caps each root namespace at 15% of the worker limit' do
      expect(scope).to have_attributes(type: :root_namespace)
      expect(scope.limit_for(100)).to eq(15)
    end

    context 'when the mergeability_check_concurrency_limit_scope flag is disabled' do
      before do
        stub_feature_flags(mergeability_check_concurrency_limit_scope: false)
      end

      it 'does not scope the worker' do
        expect(scope).to be_nil
      end
    end
  end

  describe '#perform' do
    context 'when merge request does not exist' do
      it 'does not execute MergeabilityCheckService' do
        expect(MergeRequests::MergeabilityCheckService).not_to receive(:new)

        expect(Sidekiq.logger).to receive(:error).once
          .with(
            merge_request_id: 1,
            worker: "MergeRequestMergeabilityCheckWorker",
            message: 'Failed to find merge request')

        subject.perform(1)
      end
    end

    context 'when merge request exists' do
      let(:merge_request) { create(:merge_request) }

      it 'executes MergeabilityCheckService' do
        expect_next_instance_of(MergeRequests::MergeabilityCheckService, merge_request) do |service|
          expect(service).to receive(:execute).and_return(double(error?: false))
        end

        subject.perform(merge_request.id)
      end

      it 'leaves marking the merge request as checking to the check, once it holds the lease' do
        merge_request.mark_as_unchecked!

        expect_next_instance_of(MergeRequests::MergeabilityCheckService, merge_request) do |service|
          expect(service).to receive(:execute).with(recheck: false, retry_lease: false, mark_as_checking: true) do
            expect(merge_request.reload).to be_unchecked

            double(error?: false)
          end
        end

        subject.perform(merge_request.id)
      end

      context 'when another check holds the lease', :clean_gitlab_redis_shared_state do
        before do
          merge_request.mark_as_unchecked!

          Gitlab::ExclusiveLease.skipping_transaction_check do
            Gitlab::ExclusiveLease.new("mergeability_check:#{merge_request.id}", timeout: 1.minute).try_obtain
          end
        end

        it 'leaves the merge request unchecked' do
          subject.perform(merge_request.id)

          expect(merge_request.reload).to be_unchecked
        end
      end

      context 'when mergeability_check_skip_enqueue_while_running is disabled' do
        before do
          stub_feature_flags(mergeability_check_skip_enqueue_while_running: false)
        end

        it 'marks the merge request as checking before running the check' do
          merge_request.mark_as_unchecked!

          expect_next_instance_of(MergeRequests::MergeabilityCheckService, merge_request) do |service|
            expect(service).to receive(:execute).with(recheck: false, retry_lease: false, mark_as_checking: false) do
              expect(merge_request.reload).to be_checking

              double(error?: false)
            end
          end

          subject.perform(merge_request.id)
        end

        it 'does not overwrite a merge status written after the merge request was loaded' do
          merge_request.mark_as_unchecked!

          allow(MergeRequest).to receive(:find_by_id).and_wrap_original do |method, id|
            method.call(id).tap { MergeRequest.find(id).mark_as_mergeable! }
          end

          expect_next_instance_of(MergeRequests::MergeabilityCheckService) do |service|
            expect(service).to receive(:execute).and_return(double(error?: true, message: 'Failed to obtain a lock'))
          end

          subject.perform(merge_request.id)

          expect(merge_request.reload).to be_can_be_merged
        end
      end

      it 'does not overwrite a merge status written after the merge request was loaded' do
        merge_request.mark_as_unchecked!

        allow(MergeRequest).to receive(:find_by_id).and_wrap_original do |method, id|
          method.call(id).tap { MergeRequest.find(id).mark_as_mergeable! }
        end

        # Stop right after the mark under the lease, before the check writes a status itself.
        allow_next_instance_of(MergeRequests::MergeabilityCheckService) do |service|
          allow(service).to receive(:check_mergeability).and_return(ServiceResponse.error(message: 'stopped'))
        end

        subject.perform(merge_request.id)

        expect(merge_request.reload).to be_can_be_merged
      end

      it 'structurally logs a failed mergeability check' do
        expect_next_instance_of(MergeRequests::MergeabilityCheckService, merge_request) do |service|
          expect(service).to receive(:execute).and_return(double(error?: true, message: "solar flares"))
        end

        expect(Sidekiq.logger).to receive(:error).once
          .with(
            'correlation_id' => an_instance_of(String),
            merge_request_id: merge_request.id,
            worker: "MergeRequestMergeabilityCheckWorker",
            message: 'Failed to check mergeability of merge request: solar flares')

        subject.perform(merge_request.id)
      end
    end

    it_behaves_like 'an idempotent worker' do
      let(:merge_request) { create(:merge_request) }
      let(:job_args) { [merge_request.id] }

      it 'is mergeable' do
        subject

        expect(merge_request).to be_mergeable
      end
    end
  end
end
