# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Security::ScanProfiles::ProcessGroupTransferEventsWorker, feature_category: :security_testing_configuration do
  let(:worker) { described_class.new }
  let(:group_transfer_event) do
    Groups::GroupTransferedEvent.new(data: {
      group_id: group_id,
      old_root_namespace_id: old_root_namespace_id,
      new_root_namespace_id: new_root_namespace_id
    })
  end

  let_it_be(:old_root_namespace) { create(:group) }
  let_it_be(:new_root_namespace) { create(:group) }
  let_it_be(:subgroup) { create(:group, parent: new_root_namespace) }
  let_it_be(:old_root_profile) { create(:security_scan_profile, namespace: old_root_namespace) }
  let_it_be(:root_group) { create(:group) }
  let_it_be(:scan_profile1) { create(:security_scan_profile, namespace: root_group, name: "scan profile 1") }
  let_it_be(:scan_profile2) { create(:security_scan_profile, namespace: root_group, name: "scan profile 2") }

  let(:group_id) { subgroup.id }
  let(:old_root_namespace_id) { old_root_namespace.id }
  let(:new_root_namespace_id) { new_root_namespace.id }
  let(:cleanup_worker) { Security::ScanProfiles::CleanOldNamespaceConnectionsWorker }
  let(:delete_profiles_worker) { Security::ScanProfiles::DeleteScanProfilesWorker }
  let(:sync_worker) { Security::ScanProfiles::UpdateTraversalIdsWorker }

  subject(:perform) { worker.handle_event(group_transfer_event) }

  describe '#perform' do
    before do
      allow(cleanup_worker).to receive(:perform_async)
      allow(delete_profiles_worker).to receive(:perform_async)
    end

    context 'when root namespace has not changed' do
      let(:old_root_namespace_id) { new_root_namespace.id }

      it 'does not schedule the cleanup or delete workers' do
        perform

        expect(cleanup_worker).not_to have_received(:perform_async)
        expect(delete_profiles_worker).not_to have_received(:perform_async)
      end

      # The associations survive a move inside the same root namespace, but every
      # project underneath has a new path, so their traversal_ids are now stale.
      context 'when a project in the group has a scan profile attached' do
        let_it_be(:new_root_profile) { create(:security_scan_profile, namespace: new_root_namespace) }
        let_it_be(:attached_project) { create(:project, namespace: subgroup) }
        let_it_be(:unattached_project) { create(:project, namespace: subgroup) }

        let_it_be(:association) do
          create(:security_scan_profile_project, scan_profile: new_root_profile, project: attached_project)
        end

        it 'schedules a traversal_ids sync for the attached projects only' do
          expect(sync_worker).to receive(:perform_in).with(0, [attached_project.id])

          perform
        end

        context 'when the attached projects span several batches' do
          before do
            stub_const("#{described_class}::BATCH_SIZE", 1)
            create(:security_scan_profile_project, scan_profile: new_root_profile,
              project: create(:project, namespace: subgroup))
          end

          it 'spaces the batches out' do
            expect(sync_worker).to receive(:perform_in).with(0, anything).ordered
            expect(sync_worker).to receive(:perform_in).with(described_class::BATCH_DELAY, anything).ordered

            perform
          end
        end

        context 'when the only scan profile in the root namespace is soft-deleted' do
          before do
            Security::ScanProfile.id_in(new_root_profile.id).update_all(deleted_at: Time.current)
          end

          it 'does not schedule a traversal_ids sync' do
            expect(Gitlab::Database::NamespaceProjectIdsEachBatch).not_to receive(:new)
            expect(sync_worker).not_to receive(:perform_in)

            perform
          end
        end
      end

      context 'when no project in the group has a scan profile attached' do
        before do
          create(:security_scan_profile, namespace: new_root_namespace)
        end

        it 'does not schedule a traversal_ids sync' do
          expect(sync_worker).not_to receive(:perform_in)

          perform
        end
      end

      context 'when the root namespace has no scan profiles' do
        it 'does not walk the hierarchy' do
          expect(Gitlab::Database::NamespaceProjectIdsEachBatch).not_to receive(:new)
          expect(sync_worker).not_to receive(:perform_in)

          perform
        end
      end
    end

    context 'when moved group no longer exists' do
      let(:group_id) { non_existing_record_id }

      it 'does not schedule any workers' do
        perform

        expect(cleanup_worker).not_to have_received(:perform_async)
        expect(delete_profiles_worker).not_to have_received(:perform_async)
      end
    end

    context 'when root namespace has changed and group exists' do
      context 'when group was a subgroup (moved between different root namespaces)' do
        it 'schedules cleanup worker to delete project connections' do
          perform

          expect(cleanup_worker).to have_received(:perform_async).with(subgroup.id, true)
        end

        it 'does not schedule delete profiles worker' do
          perform

          expect(delete_profiles_worker).not_to have_received(:perform_async)
        end

        context 'when the old root namespace has no scan profiles' do
          before do
            Security::ScanProfile.by_namespace(old_root_namespace).delete_all
          end

          it 'does not schedule any workers', :aggregate_failures do
            perform

            expect(cleanup_worker).not_to have_received(:perform_async)
            expect(delete_profiles_worker).not_to have_received(:perform_async)
          end
        end
      end

      context 'when group was a root and is now a subgroup' do
        let_it_be(:new_parent) { create(:group) }

        let(:group_id) { root_group.id }
        let(:old_root_namespace_id) { root_group.id }
        let(:new_root_namespace_id) { new_parent.id }

        before do
          root_group.reload.update!(parent: new_parent)
        end

        it 'schedules delete profiles worker with profile ids' do
          perform

          expected_ids = [scan_profile1, scan_profile2].map(&:id)
          expect(delete_profiles_worker).to have_received(:perform_async) do |profile_ids, group_id|
            expect(profile_ids).to match_array(expected_ids)
            expect(group_id).to eq(root_group.id)
          end
        end

        it 'does not schedule cleanup worker' do
          perform

          expect(cleanup_worker).not_to have_received(:perform_async)
        end
      end
    end
  end
end
