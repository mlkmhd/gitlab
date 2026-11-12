# frozen_string_literal: true

require 'spec_helper'

RSpec.describe MergeRequests::MergeabilityCheckService, :clean_gitlab_redis_shared_state, feature_category: :code_review_workflow do
  shared_examples_for 'unmergeable merge request' do
    it 'updates or keeps merge status as cannot_be_merged' do
      subject

      expect(merge_request.merge_status).to eq('cannot_be_merged')
    end

    it 'does not change the merge ref HEAD' do
      merge_ref_head = merge_request.merge_ref_head

      subject

      expect(merge_request.reload.merge_ref_head).to eq merge_ref_head
    end

    it 'returns ServiceResponse.error' do
      result = subject

      expect(result).to be_a(ServiceResponse)
      expect(result).to be_error
    end
  end

  shared_examples_for 'mergeable merge request' do
    it 'updates or keeps merge status as can_be_merged' do
      subject

      expect(merge_request.merge_status).to eq('can_be_merged')
    end

    it 'reloads merge head diff' do
      expect_next_instance_of(MergeRequests::ReloadMergeHeadDiffService) do |service|
        expect(service).to receive(:execute)
      end

      subject
    end

    it 'update diff discussion positions' do
      expect_next_instance_of(Discussions::CaptureDiffNotePositionsService) do |service|
        expect(service).to receive(:execute)
      end

      subject
    end

    it 'updates the merge ref' do
      expect { subject }.to change { merge_request.merge_ref_head }.from(nil)
    end

    it 'returns ServiceResponse.success' do
      result = subject

      expect(result).to be_a(ServiceResponse)
      expect(result).to be_success
    end

    it 'ServiceResponse has merge_ref_head payload' do
      result = subject

      expect(result.payload.keys).to contain_exactly(:merge_ref_head)
      expect(result.payload[:merge_ref_head].keys)
        .to contain_exactly(:commit_id, :target_id, :source_id)
    end
  end

  let(:project) { create(:project, :repository) }
  let(:merge_request) { create(:merge_request, merge_status: :unchecked, source_project: project, target_project: project) }

  describe '#async_execute' do
    it 'leaves the merge status for the worker to update' do
      described_class.new(merge_request).async_execute

      expect(merge_request).to be_unchecked
    end

    it 'enqueues MergeRequestMergeabilityCheckWorker with the project root namespace in context' do
      expect(MergeRequestMergeabilityCheckWorker).to receive(:perform_async).with(merge_request.id) do
        expect(Gitlab::ApplicationContext.current)
          .to include('meta.root_namespace' => project.root_namespace.full_path)
      end

      described_class.new(merge_request).async_execute
    end

    context 'when read-only DB' do
      before do
        allow(Gitlab::Database).to receive(:read_only?).and_return(true)
      end

      it 'does not enqueue MergeRequestMergeabilityCheckWorker' do
        expect(MergeRequestMergeabilityCheckWorker).not_to receive(:perform_async)

        described_class.new(merge_request).async_execute
      end
    end

    context 'when another check holds the lease' do
      before do
        merge_request.update_column(:merge_status, merge_status)

        Gitlab::ExclusiveLease.skipping_transaction_check do
          Gitlab::ExclusiveLease.new("mergeability_check:#{merge_request.id}", timeout: 1.minute).try_obtain
        end
      end

      context 'when the status has not moved since that check started' do
        where(merge_status: %w[checking cannot_be_merged_rechecking])

        with_them do
          it 'does not enqueue MergeRequestMergeabilityCheckWorker' do
            expect(MergeRequestMergeabilityCheckWorker).not_to receive(:perform_async)

            described_class.new(merge_request).async_execute
          end
        end

        context 'when mergeability_check_skip_enqueue_while_running is disabled' do
          let(:merge_status) { 'checking' }

          before do
            stub_feature_flags(mergeability_check_skip_enqueue_while_running: false)
          end

          it 'enqueues MergeRequestMergeabilityCheckWorker' do
            expect(MergeRequestMergeabilityCheckWorker).to receive(:perform_async).with(merge_request.id)

            described_class.new(merge_request).async_execute
          end
        end
      end

      context 'when a push reset the status while that check runs' do
        where(merge_status: %w[unchecked cannot_be_merged_recheck])

        with_them do
          it 'enqueues MergeRequestMergeabilityCheckWorker' do
            expect(MergeRequestMergeabilityCheckWorker).to receive(:perform_async).with(merge_request.id)

            described_class.new(merge_request).async_execute
          end
        end
      end
    end

    context 'when the status is checking but no check holds the lease' do
      before do
        merge_request.update_column(:merge_status, 'checking')
      end

      it 'enqueues MergeRequestMergeabilityCheckWorker to replace the check that died' do
        expect(MergeRequestMergeabilityCheckWorker).to receive(:perform_async).with(merge_request.id)

        described_class.new(merge_request).async_execute
      end
    end

    # Reads skip enqueuing while the running check holds the lease, and a source push
    # then makes it discard its result, so a check for the new source must still be queued.
    # See https://gitlab.com/gitlab-org/gitlab/-/merge_requests/267363#note_4157570417
    context 'when the source moves while a check runs' do
      let(:id) { merge_request.id }

      before do
        project.add_developer(merge_request.author)
      end

      def run_check
        interleaved = false

        allow_next_instance_of(described_class) do |service|
          allow(service).to receive(:merge_to_ref).and_wrap_original do |original|
            unless interleaved
              interleaved = true
              yield
            end

            original.call
          end
        end

        Gitlab::ExclusiveLease.skipping_transaction_check do
          MergeRequestMergeabilityCheckWorker.new.perform(id)
        end
      end

      def reload_diff
        MergeRequest.find(id).create_merge_request_diff
      end

      def uncheck
        MergeRequest.batch_mark_as_unchecked([id])
      end

      def read
        MergeRequest.find(id).check_mergeability(async: true)
      end

      def queued_checks
        MergeRequestMergeabilityCheckWorker.jobs.count { |job| job['args'] == [id] }
      end

      context 'when another job cannot take the lease' do
        it 'leaves the merge request unchecked with a check queued' do
          run_check do
            reload_diff
            uncheck
            MergeRequestMergeabilityCheckWorker.new.perform(id)
            read
          end

          expect(MergeRequest.find(id)).to be_unchecked
          expect(queued_checks).to eq(1)
        end
      end

      context 'when the batch worker cannot take the lease' do
        it 'leaves the merge request unchecked with a check queued' do
          run_check do
            reload_diff
            uncheck
            MergeRequests::MergeabilityCheckBatchWorker.new.perform([id], merge_request.author_id)
            read
          end

          expect(MergeRequest.find(id)).to be_unchecked
          expect(queued_checks).to eq(1)
        end
      end

      context 'when a read lands before the push unchecks the merge request' do
        it 'queues a check' do
          run_check do
            reload_diff
            read
            uncheck
          end

          expect(queued_checks).to eq(1)
        end
      end
    end
  end

  describe '#execute' do
    let(:repo) { project.repository }

    subject { described_class.new(merge_request).execute }

    def execute_within_threads(amount:, retry_lease: true)
      threads = []

      amount.times do
        # Let's use a different object for each thread to get closer
        # to a real world scenario.
        mr = MergeRequest.find(merge_request.id)

        threads << Thread.new do
          Gitlab::ExclusiveLease.skipping_transaction_check do
            described_class.new(mr).execute(retry_lease: retry_lease)
          end
        end
      end

      threads.each(&:join)
      threads
    end

    before do
      project.add_developer(merge_request.author)
    end

    it_behaves_like 'mergeable merge request'

    it 'does not queue another check' do
      expect(MergeRequestMergeabilityCheckWorker).not_to receive(:perform_async)

      subject
    end

    context 'when mark_as_checking is true' do
      subject { described_class.new(merge_request).execute(retry_lease: false, mark_as_checking: true) }

      it 'marks the merge request as checking once it holds the lease' do
        expect(MergeRequest).to receive(:batch_mark_as_checking).with([merge_request.id])
          .and_wrap_original do |original, ids|
            expect(Gitlab::ExclusiveLease.get_uuid("mergeability_check:#{merge_request.id}")).to be_present

            original.call(ids)
          end

        subject
      end

      context 'when another check holds the lease' do
        before do
          Gitlab::ExclusiveLease.skipping_transaction_check do
            Gitlab::ExclusiveLease.new("mergeability_check:#{merge_request.id}", timeout: 1.minute).try_obtain
          end
        end

        it 'leaves the merge request unchecked' do
          subject

          expect(merge_request.reload).to be_unchecked
        end
      end

      context 'when the loaded merge request is not awaiting a check' do
        # The caller loaded a decided merge request, and a push unchecked the row since. This check
        # writes nothing, so marking the row checking would make reads skip with nothing to follow.
        before do
          merge_request.update_column(:merge_status, 'can_be_merged')
          MergeRequest.batch_mark_as_unchecked([merge_request.id])
        end

        it 'leaves the merge request unchecked' do
          subject

          expect(merge_request.reload).to be_unchecked
        end
      end
    end

    context 'when concurrent calls' do
      it 'waits first lock and returns "cached" result in subsequent calls' do
        threads = execute_within_threads(amount: 3)
        results = threads.map { |t| t.value.status }

        expect(results).to contain_exactly(:success, :success, :success)
      end

      it 'writes the merge-ref once' do
        service = instance_double(MergeRequests::MergeToRefService)

        expect(MergeRequests::MergeToRefService).to receive(:new).once { service }
        expect(service).to receive(:execute).once.and_return(success: true)

        execute_within_threads(amount: 3)
      end

      it 'resets one merge request upon execution' do
        expect_next_instance_of(MergeRequests::ReloadMergeHeadDiffService) do |svc|
          expect(svc).to receive(:execute).and_return(status: :success)
        end

        expect_any_instance_of(MergeRequest).to receive(:reset).once.and_call_original

        execute_within_threads(amount: 2)
      end

      context 'when retry_lease flag is false' do
        it 'the first call succeeds, subsequent concurrent calls get a lock error response' do
          threads = execute_within_threads(amount: 3, retry_lease: false)
          results = threads.map { |t| [t.value.status, t.value.message] }

          expect(results).to contain_exactly(
            [:error, 'Failed to obtain a lock'],
            [:error, 'Failed to obtain a lock'],
            [:success, nil]
          )
        end
      end
    end

    context 'when broken' do
      before do
        expect(merge_request).to receive(:broken?).and_return(true)
      end

      it_behaves_like 'unmergeable merge request'

      it 'returns ServiceResponse.error' do
        result = subject

        expect(result).to be_a(ServiceResponse)
        expect(result.error?).to be(true)
        expect(result.message).to eq('Merge request is not mergeable')
        expect(result.reason).to be_nil
      end
    end

    context 'when mergeability status changes after merge ref is successfully updated' do
      before do
        allow_next_instance_of(::MergeRequests::MergeabilityCheckService) do |service|
          allow(service).to(receive(:reload_merge_head_diff)).and_wrap_original do |original|
            # update the merge request via a different record to simulate external race
            MergeRequest.find(merge_request.id).mark_as_unchecked
            original.call
          end
        end
      end

      it 'returns ServiceResponse.error with reason :merge_status_race' do
        result = subject

        expect(result).to be_a(ServiceResponse)
        expect(result.error?).to be(true)
        expect(result.message).to eq('Merge request is not mergeable')
        expect(result.reason).to eq(:merge_status_race)
      end
    end

    context 'when the row has no latest diff id but the merge request has a diff' do
      # Every check reads the newest diff and so discards its result, so requeuing would loop.
      before do
        merge_request.update_column(:latest_merge_request_diff_id, nil)
      end

      it 'discards the merge status without queuing another check' do
        expect(MergeRequestMergeabilityCheckWorker).not_to receive(:perform_async)

        expect(subject.reason).to eq(described_class::STALE_MERGE_STATUS_DISCARDED)
      end
    end

    context 'when the merge request is retargeted while the check is running' do
      # The caller holds a record loaded before the retarget, so the merge status it
      # computes answers the question for the old target branch. The factory targets
      # `feature`, so retarget to something else, and via `update_column` so that
      # `reload_diff_if_branch_changed` does not also move the source diff - this
      # example is about the target branch alone.
      # See https://gitlab.com/gitlab-org/gitlab/-/work_items/606487
      before do
        MergeRequest.find(merge_request.id).tap do |current|
          current.update_column(:target_branch, 'improve/awesome')
          current.mark_as_unmergeable
        end
      end

      it 'discards the merge status computed for the old target branch' do
        expect(merge_request.target_branch).to eq('feature') # the caller is stale

        expect { subject }.not_to change { MergeRequest.find(merge_request.id).merge_status }
          .from('cannot_be_merged')
      end

      it 'reports the merge status as discarded' do
        result = subject

        expect(result).to be_error
        expect(result.reason).to eq(described_class::STALE_MERGE_STATUS_DISCARDED)
      end

      it 'does not leave the discarded status on the in-memory record' do
        subject

        expect(merge_request.merge_status).not_to eq('can_be_merged')
      end

      it 'does not run the callbacks of the discarded transition' do
        expect(GraphqlTriggers).not_to receive(:merge_request_merge_status_updated)
        expect(AutoMergeProcessWorker).not_to receive(:perform_async)

        subject
      end

      it 'does not queue another check, because the row already has a status for its inputs' do
        expect(MergeRequestMergeabilityCheckWorker).not_to receive(:perform_async)

        subject
      end

      context 'when the row still awaits a check' do
        before do
          MergeRequest.where(id: merge_request.id).update_all(merge_status: 'unchecked')
        end

        it 'queues the next check once the lease is released' do
          expect(MergeRequestMergeabilityCheckWorker).to receive(:perform_async).with(merge_request.id) do
            expect(Gitlab::ExclusiveLease.get_uuid("mergeability_check:#{merge_request.id}")).to be(false)
          end

          subject
        end

        context 'when the merge request is deleted before the next check is queued' do
          before do
            allow(MergeRequest).to receive(:find_by_id).and_call_original
            allow(MergeRequest).to receive(:find_by_id).with(merge_request.id).and_return(nil)
          end

          it 'does not queue another check' do
            expect(MergeRequestMergeabilityCheckWorker).not_to receive(:perform_async)

            subject
          end
        end

        context 'when mergeability_check_skip_enqueue_while_running is disabled' do
          before do
            stub_feature_flags(mergeability_check_skip_enqueue_while_running: false)
          end

          it 'does not queue another check' do
            expect(MergeRequestMergeabilityCheckWorker).not_to receive(:perform_async)

            subject
          end
        end
      end

      context 'when the merge request is broken' do
        before do
          allow(merge_request).to receive(:broken?).and_return(true)
        end

        # The discarded status here is the value the row already holds, so only the
        # record shows whether the transition ran.
        it 'discards the unmergeable status too' do
          expect { subject }.not_to change { merge_request.merge_status }.from('unchecked')
        end

        it 'reports the merge status as discarded' do
          expect(subject.reason).to eq(described_class::STALE_MERGE_STATUS_DISCARDED)
        end
      end
    end

    context 'when the source diff is reloaded while the check is running' do
      # The caller holds the diff its merge status was computed from, but a newer one
      # has since become the latest, so that status answers for an old source SHA.
      before do
        merge_request.merge_request_diff # load the caller's diff before it is superseded

        MergeRequest.find(merge_request.id).tap do |current|
          current.create_merge_request_diff
          current.mark_as_unmergeable
        end
      end

      it 'discards the merge status computed for the old source SHA' do
        expect { subject }.not_to change { MergeRequest.find(merge_request.id).merge_status }
          .from('cannot_be_merged')
      end
    end

    context 'when a merge status was already written for the same source and target' do
      # The claim compares inputs, not ordering. Requiring the row to still await a
      # status would make the first writer win, so a check that ran on inputs which
      # have since been restored would lock out the correct status behind it, turning
      # a race that used to self-correct into a permanent wrong answer.
      before do
        MergeRequest.find(merge_request.id).mark_as_unmergeable
      end

      it 'still writes the merge status' do
        expect { subject }.to change { MergeRequest.find(merge_request.id).merge_status }
          .from('cannot_be_merged').to('can_be_merged')
      end
    end

    context 'when it cannot be merged on git' do
      let(:merge_request) do
        create(
          :merge_request,
          merge_status: :unchecked,
          source_branch: 'conflict-resolvable',
          source_project: project,
          target_branch: 'conflict-start'
        )
      end

      it 'returns ServiceResponse.error and keeps merge status as cannot_be_merged and reason is nil' do
        result = subject

        expect(merge_request.merge_status).to eq('cannot_be_merged')
        expect(result).to be_a(ServiceResponse)
        expect(result.error?).to be(true)
        expect(result.message).to eq('Merge request is not mergeable')
        expect(result.reason).to be_nil
      end
    end

    context 'when MR cannot be merged and has no merge ref' do
      before do
        merge_request.mark_as_unmergeable!
      end

      it_behaves_like 'unmergeable merge request'

      it 'returns ServiceResponse.error' do
        result = subject

        expect(result).to be_a(ServiceResponse)
        expect(result.error?).to be(true)
        expect(result.message).to eq('Merge request is not mergeable')
      end
    end

    context 'when MR cannot be merged and has outdated merge ref' do
      before do
        MergeRequests::MergeToRefService.new(project: project, current_user: merge_request.author).execute(merge_request)
        merge_request.mark_as_unmergeable!
      end

      it_behaves_like 'unmergeable merge request'

      it 'returns ServiceResponse.error' do
        result = subject

        expect(result).to be_a(ServiceResponse)
        expect(result.error?).to be(true)
        expect(result.message).to eq('Merge request is not mergeable')
      end
    end

    context 'when merge request is not given' do
      subject { described_class.new(nil).execute }

      it 'returns ServiceResponse.error' do
        result = subject

        expect(result).to be_a(ServiceResponse)
        expect(result.message).to eq('Invalid argument')
      end
    end

    context 'when read-only DB' do
      it 'returns ServiceResponse.error' do
        allow(Gitlab::Database).to receive(:read_only?).and_return(true)

        result = subject

        expect(result).to be_a(ServiceResponse)
        expect(result.message).to eq('Unsupported operation')
      end
    end

    context 'when fails to update the merge-ref' do
      before do
        expect_next_instance_of(MergeRequests::MergeToRefService) do |merge_to_ref|
          expect(merge_to_ref).to receive(:execute).and_return(status: :failed)
        end
      end

      it_behaves_like 'unmergeable merge request'

      it 'does not reload merge head diff' do
        expect(MergeRequests::ReloadMergeHeadDiffService).not_to receive(:new)

        subject
      end

      it 'returns ServiceResponse.error' do
        result = subject

        expect(result).to be_a(ServiceResponse)
        expect(result.error?).to be(true)
        expect(result.message).to eq('Merge request is not mergeable')
      end
    end

    context 'when the merge-ref commit cannot be found' do
      before do
        expect_next_instance_of(MergeRequests::MergeToRefService) do |merge_to_ref|
          expect(merge_to_ref).to receive(:execute)
            .and_raise(MergeRequests::MergeToRefService::MergeCommitNotFoundError)
        end
      end

      it 'propagates the error without marking the merge request as unmergeable' do
        expect { subject }.to raise_error(MergeRequests::MergeToRefService::MergeCommitNotFoundError)

        expect(MergeRequest.find(merge_request.id).merge_status).not_to eq('cannot_be_merged')
      end
    end

    context 'recheck enforced' do
      subject { described_class.new(merge_request).execute(recheck: true) }

      context 'when MR is marked as mergeable, but repo is not mergeable and MR is not opened' do
        before do
          # Making sure that we don't touch the merge-status after
          # the MR is not opened any longer. Source branch might
          # have been removed, etc.
          allow(merge_request).to receive(:broken?).and_return(true)
          merge_request.mark_as_mergeable!
          merge_request.close!
        end

        it 'returns ServiceResponse.error' do
          result = subject

          expect(result).to be_a(ServiceResponse)
          expect(result.error?).to be(true)
          expect(result.message).to eq('Merge ref cannot be updated')
          expect(result.payload).to be_empty
        end

        it 'does not change the merge status' do
          expect { subject }.not_to change { merge_request.merge_status }.from('can_be_merged')
        end
      end

      context 'when MR is mergeable but merge-ref does not exists' do
        before do
          merge_request.mark_as_mergeable!
        end

        it_behaves_like 'mergeable merge request'
      end

      context 'when MR is mergeable but merge-ref is already updated' do
        before do
          MergeRequests::MergeToRefService.new(project: project, current_user: merge_request.author).execute(merge_request)
          merge_request.mark_as_mergeable!
        end

        it 'returns ServiceResponse.success' do
          result = subject

          expect(result).to be_a(ServiceResponse)
          expect(result).to be_success
          expect(result.payload[:merge_ref_head]).to be_present
        end

        it 'does not recreate the merge-ref' do
          expect(MergeRequests::MergeToRefService).not_to receive(:new)

          subject
        end

        it 'does not reload merge head diff' do
          expect(MergeRequests::ReloadMergeHeadDiffService).not_to receive(:new)

          subject
        end
      end
    end
  end

  describe 'the deferred MergeRequests::AfterCreateCloudEvent' do
    let(:merge_request) { create(:merge_request, merge_status: :unchecked) }

    subject(:execute) { described_class.new(merge_request).execute }

    shared_examples 'asking the publisher to publish' do
      it 'gives the publisher its one chance to publish' do
        expect_next_instance_of(MergeRequests::AfterCreateEventPublisher, merge_request) do |publisher|
          expect(publisher).to receive(:publish_deferred)
        end

        execute
      end
    end

    it_behaves_like 'asking the publisher to publish'

    context 'when the merge request is broken' do
      before do
        allow(merge_request).to receive(:broken?).and_return(true)
      end

      it_behaves_like 'asking the publisher to publish'
    end

    context 'when the merge to ref fails (for example, conflicts)' do
      before do
        allow_next_instance_of(MergeRequests::MergeToRefService) do |service|
          allow(service).to receive(:execute).and_return(status: :error)
        end
      end

      it_behaves_like 'asking the publisher to publish'
    end

    # The merge head diff is what code-owner approval rules are synced against, so a
    # failed reload means the event is published without them. No later checkpoint is
    # guaranteed, and stranding the event is worse.
    context 'when the merge head diff reload fails' do
      before do
        allow_next_instance_of(MergeRequests::ReloadMergeHeadDiffService) do |service|
          allow(service).to receive(:execute).and_return(status: :error, message: 'failed')
        end
      end

      it_behaves_like 'asking the publisher to publish'
    end
  end
end
