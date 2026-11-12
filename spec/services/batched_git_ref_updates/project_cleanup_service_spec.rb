# frozen_string_literal: true

require 'spec_helper'

RSpec.describe BatchedGitRefUpdates::ProjectCleanupService, :clean_gitlab_redis_shared_state,
  feature_category: :gitaly do
  let(:service) { described_class.new(project1.id) }
  let_it_be(:project1) { create(:project, :small_repo) }
  let_it_be(:project2) { create(:project, :small_repo) }
  let_it_be(:project1_ref1) do
    BatchedGitRefUpdates::Deletion.create!(project_id: project1.id, ref: 'refs/test/project1-ref1')
  end

  let_it_be(:project1_ref2) do
    BatchedGitRefUpdates::Deletion.create!(project_id: project1.id, ref: 'refs/test/project1-ref2')
  end

  let_it_be(:project1_ref3) do
    BatchedGitRefUpdates::Deletion.create!(project_id: project1.id, ref: 'refs/test/already-processed',
      status: :processed)
  end

  let_it_be(:project2_ref1) do
    BatchedGitRefUpdates::Deletion.create!(project_id: project2.id, ref: 'refs/test/project2-ref1')
  end

  describe '#execute' do
    before do
      project1.repository.create_ref('HEAD', 'refs/test/ref-to-not-be-deleted')
      project1.repository.create_ref('HEAD', project1_ref1.ref)
      project1.repository.create_ref('HEAD', project1_ref2.ref)
      project1.repository.create_ref('HEAD', 'refs/test/already-processed')
      project2.repository.create_ref('HEAD', project2_ref1.ref)
    end

    it 'deletes the named refs in batches for the given project only' do
      expect(test_refs(project1)).to include(
        'refs/test/ref-to-not-be-deleted',
        'refs/test/already-processed',
        'refs/test/project1-ref1',
        'refs/test/project1-ref1',
        'refs/test/project1-ref2')

      service.execute

      expect(test_refs(project1)).to include(
        'refs/test/already-processed',
        'refs/test/ref-to-not-be-deleted')

      expect(test_refs(project1)).not_to include(
        'refs/test/project1-ref1',
        'refs/test/project1-ref2')

      expect(test_refs(project2)).to include('refs/test/project2-ref1')
    end

    it 'handles duplicates' do
      BatchedGitRefUpdates::Deletion.create!(project_id: project1.id, ref: 'refs/test/some-duplicate')
      BatchedGitRefUpdates::Deletion.create!(project_id: project1.id, ref: 'refs/test/some-duplicate')

      service.execute

      expect(test_refs(project1)).not_to include('refs/test/some-duplicate')
    end

    it 'marks the processed BatchedGitRefUpdates::Deletion as processed' do
      service.execute

      expect(BatchedGitRefUpdates::Deletion.status_pending.map(&:ref)).to contain_exactly('refs/test/project2-ref1')
      expect(BatchedGitRefUpdates::Deletion.status_processed.map(&:ref)).to contain_exactly(
        'refs/test/project1-ref1',
        'refs/test/project1-ref2',
        'refs/test/already-processed')
    end

    it 'returns stats' do
      result = service.execute

      expect(result[:total_deletes]).to eq(2)
    end

    it 'acquires a lock for the given project_id to avoid running duplicate instances' do
      expect(service).to receive(:in_lock) # Mock and don't yield
        .with("#{described_class}/#{project1.id}", retries: 0, ttl: described_class::LOCK_TIMEOUT)

      expect { service.execute }.not_to change { BatchedGitRefUpdates::Deletion.status_pending.count }
    end

    context 'when the project does not exist' do
      let!(:deletion_for_deleted_project) do
        BatchedGitRefUpdates::Deletion.create!(project_id: non_existing_record_id, ref: 'refs/test/deleted-project-ref')
      end

      it 'marks records as processed without attempting to delete refs' do
        result = described_class.new(non_existing_record_id).execute

        expect(result[:total_deletes]).to eq(1)
        expect(deletion_for_deleted_project.reload.status).to eq('processed')
      end
    end

    context 'when the repository does not exist' do
      let_it_be(:project_without_repo) { create(:project) }
      let!(:deletion) do
        BatchedGitRefUpdates::Deletion.create!(project_id: project_without_repo.id, ref: 'refs/test/ref1')
      end

      it 'marks records as processed' do
        result = described_class.new(project_without_repo.id).execute

        expect(result[:total_deletes]).to eq(1)
        expect(deletion.reload.status).to eq('processed')
      end
    end

    it 'stops after it reaches limit of deleted refs' do
      stub_const("#{described_class}::QUERY_BATCH_SIZE", 1)
      stub_const("#{described_class}::MAX_DELETES", 1)

      result = service.execute

      expect(result[:total_deletes]).to eq(1)
    end

    context 'when Gitaly reports a reference conflict' do
      # The gitaly gem may predate gitaly!9409, so the first delete_refs raises the mapped error here.
      let(:parent_ref) { 'refs/merge-requests/1' }
      let(:conflicting_ref) { 'refs/merge-requests/1/head' }
      let(:conflict) do
        Gitlab::Git::ReferenceConflictError.new(
          existing_reference_name: parent_ref,
          conflicting_reference_name: conflicting_ref
        )
      end

      let!(:deletion) { BatchedGitRefUpdates::Deletion.create!(project_id: project1.id, ref: conflicting_ref) }
      let(:head_sha) { project1.repository.commit('HEAD').sha }

      before do
        project1.repository.create_ref('HEAD', parent_ref)
      end

      # The service loads its own Project, so stub the Repository instances it builds.
      def stub_repository(conflicts: 1)
        conflict_batches = 0

        allow_next_instance_of(Repository) do |repository|
          allow(repository).to receive(:delete_refs).and_wrap_original do |original, *refs|
            if refs.include?(conflicting_ref)
              conflict_batches += 1
              raise conflict if conflict_batches <= conflicts
            end

            original.call(*refs)
          end

          yield repository if block_given?
        end
      end

      context 'with the repair enabled' do
        let(:keep_around_ref) { "refs/#{::Repository::REF_KEEP_AROUND}/#{head_sha}" }

        before do
          allow(Gitlab::AppLogger).to receive(:info).and_call_original
        end

        after do
          project1.repository.delete_refs(keep_around_ref)
        end

        it 'keeps the parent commit around, deletes the parent and retries the batch once' do
          # spec_helper stubs KeepAround to a no-op; run the real one.
          expect(Gitlab::Git::KeepAround).to receive(:execute).and_call_original
          stub_repository

          expect(Gitlab::AppLogger).to receive(:info).with(
            hash_including(
              message: 'Repaired stray parent reference blocking batched ref deletion',
              gl_project_id: project1.id,
              ref: parent_ref,
              conflicting_ref: conflicting_ref,
              kept_around: head_sha
            )
          )

          result = service.execute

          expect(result[:total_deletes]).to eq(3)
          expect(project1.repository.ref_exists?(parent_ref)).to be(false)
          expect(project1.repository.ref_exists?(keep_around_ref)).to be(true)
          expect(deletion.reload.status).to eq('processed')
        end

        it 'propagates a conflict that survives one repair' do
          stub_repository(conflicts: 2)

          expect { service.execute }.to raise_error(Gitlab::Git::ReferenceConflictError)
          expect(deletion.reload.status).to eq('pending')
        end

        it 'does not delete the parent when the keep-around write is reported as failed' do
          allow(Gitlab::Git::KeepAround).to receive(:execute).and_return([head_sha])
          stub_repository

          expect { service.execute }
            .to raise_error(Gitlab::Git::ReferenceConflictError, /keep-around reference could not be written/)
          expect(project1.repository.ref_exists?(parent_ref)).to be(true)
          expect(deletion.reload.status).to eq('pending')
        end

        it 'does not delete the parent when the keep-around reference is not written' do
          # the default spec_helper stub: KeepAround reports no failure and writes nothing
          stub_repository

          expect { service.execute }
            .to raise_error(Gitlab::Git::ReferenceConflictError, /keep-around reference was not written/)
          expect(project1.repository.ref_exists?(parent_ref)).to be(true)
          expect(deletion.reload.status).to eq('pending')
        end

        it 'does not delete a parent whose commit cannot be resolved' do
          stub_repository do |repository|
            allow(repository).to receive(:commit).with(parent_ref).and_return(nil)
          end

          expect { service.execute }
            .to raise_error(Gitlab::Git::ReferenceConflictError, /parent commit could not be resolved/)
          expect(project1.repository.ref_exists?(parent_ref)).to be(true)
          expect(deletion.reload.status).to eq('pending')
        end

        context 'when the existing reference is not a parent of the reference being deleted' do
          let(:stray_child) { "#{conflicting_ref}/stray" }
          let(:conflict) do
            Gitlab::Git::ReferenceConflictError.new(
              existing_reference_name: stray_child,
              conflicting_reference_name: conflicting_ref
            )
          end

          before do
            # git cannot hold the bare parent and a reference below it at once
            project1.repository.delete_refs(parent_ref)
            project1.repository.create_ref('HEAD', stray_child)
          end

          after do
            project1.repository.delete_refs(stray_child)
          end

          it 'leaves the existing reference in place' do
            expect(Gitlab::Git::KeepAround).not_to receive(:execute)
            stub_repository

            expect { service.execute }
              .to raise_error(Gitlab::Git::ReferenceConflictError, /not a parent of the reference being deleted/)
            expect(project1.repository.ref_exists?(stray_child)).to be(true)
            expect(deletion.reload.status).to eq('pending')
          end
        end
      end

      context 'with the repair disabled' do
        before do
          stub_feature_flags(batched_git_ref_updates_repair_stray_parent: false)
        end

        it 'raises the conflict and leaves the parent reference in place' do
          stub_repository

          expect { service.execute }.to raise_error(Gitlab::Git::ReferenceConflictError)
          expect(project1.repository.ref_exists?(parent_ref)).to be(true)
          expect(deletion.reload.status).to eq('pending')
        end
      end
    end

    context 'when the batch keeps failing' do
      let(:failure) { Gitlab::Git::ReferencesLockedError.new('locked') }
      let(:backoff_key) { "#{described_class::BACKOFF_KEY_PREFIX}:#{project1.id}" }

      def redis_backoff
        Gitlab::Redis::SharedState.with { |redis| redis.hgetall(backoff_key) }
      end

      def fail_delete_refs
        allow_next_instance_of(Repository) do |repository|
          allow(repository).to receive(:delete_refs).and_raise(failure)
        end
      end

      it 'records the failure and skips the project until the retry time' do
        fail_delete_refs
        expect { service.execute }.to raise_error(Gitlab::Git::ReferencesLockedError)

        expect(redis_backoff['failures']).to eq('1')
        retry_after = Time.zone.at(redis_backoff['retry_after'].to_i)
        expect(retry_after).to be_within(5.seconds).of(described_class::BACKOFF_BASE.from_now)

        # the scheduler enqueues again a minute later; inside the window the
        # project is not even loaded
        expect(Project).not_to receive(:find_by_id)

        result = described_class.new(project1.id).execute

        expect(result).to eq({ total_deletes: 0, skipped_until: retry_after })
        expect(BatchedGitRefUpdates::Deletion.status_pending.for_project(project1.id).count).to eq(2)
      end

      it 'doubles the delay on each consecutive failure up to the maximum' do
        fail_delete_refs

        3.times do |n|
          travel_to(Time.zone.at(redis_backoff['retry_after'].to_i) + 1.second) if n > 0
          expect { described_class.new(project1.id).execute }.to raise_error(Gitlab::Git::ReferencesLockedError)
          expect(redis_backoff['failures']).to eq((n + 1).to_s)
          expected = [described_class::BACKOFF_BASE * (2**n), described_class::BACKOFF_MAX].min
          expect(Time.zone.at(redis_backoff['retry_after'].to_i)).to be_within(5.seconds).of(expected.from_now)
        end
      end

      it 'keeps the record longer than the longest delay' do
        stub_const("#{described_class}::BACKOFF_MAX", 3.minutes)
        fail_delete_refs

        3.times do
          travel_to(Time.zone.at(redis_backoff['retry_after'].to_i) + 1.second) if redis_backoff.present?
          expect { described_class.new(project1.id).execute }.to raise_error(Gitlab::Git::ReferencesLockedError)
        end

        ttl = Gitlab::Redis::SharedState.with { |redis| redis.ttl(backoff_key) }
        expect(ttl).to be > described_class::BACKOFF_MAX.to_i
      end

      it 'starts the delay again when the failing run deleted something first' do
        stub_const("#{described_class}::QUERY_BATCH_SIZE", 1)
        Gitlab::Redis::SharedState.with do |redis|
          redis.hset(backoff_key, 'failures', 4, 'retry_after', 1.minute.ago.to_i)
        end
        allow_next_instance_of(Repository) do |repository|
          allow(repository).to receive(:delete_refs).and_wrap_original do |original, *refs|
            raise failure if refs.include?(project1_ref2.ref)

            original.call(*refs)
          end
        end

        expect { service.execute }.to raise_error(Gitlab::Git::ReferencesLockedError)

        expect(project1_ref1.reload.status).to eq('processed')
        expect(redis_backoff['failures']).to eq('1')
        expect(Time.zone.at(redis_backoff['retry_after'].to_i))
          .to be_within(5.seconds).of(described_class::BACKOFF_BASE.from_now)
      end

      it 'clears the record after a successful run' do
        Gitlab::Redis::SharedState.with do |redis|
          redis.hset(backoff_key, 'failures', 4, 'retry_after', 1.minute.ago.to_i)
        end

        service.execute

        expect(redis_backoff).to eq({})
      end
    end

    def test_refs(project)
      project.repository.list_refs(['refs/test/']).map(&:name)
    end
  end
end
