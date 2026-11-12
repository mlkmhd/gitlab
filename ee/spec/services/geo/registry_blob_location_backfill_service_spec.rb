# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Geo::RegistryBlobLocationBackfillService, :geo, :clean_gitlab_redis_shared_state, feature_category: :geo_replication do
  include ::EE::GeoHelpers

  let(:replicator_class) { Geo::LfsObjectReplicator }
  let(:registry_class) { Geo::LfsObjectRegistry }
  let(:cursor) { Gitlab::Geo::RegistryBlobLocationBackfillCursor.new(replicator_class.replicable_name) }
  # Registry IDs come from a sequence that is not reset between examples
  let(:batch_size) { 1_000_000 }

  subject(:service) { described_class.new(replicator_class, batch_size: batch_size) }

  def expected_path(registry)
    registry.lfs_object.file.relative_path.to_s
  end

  describe '#execute' do
    it 'fills the blob path of synced registries that have none' do
      registry = create(:geo_lfs_object_registry, :synced)

      service.execute

      expect(registry.reload.blob_path).to eq(expected_path(registry))
      expect(registry.blob_path).to be_present
    end

    it 'does not complete the replicator on the first batch' do
      create(:geo_lfs_object_registry, :synced)

      service.execute

      expect(cursor).not_to be_done
    end

    it 'fills many registries in one pass' do
      registries = create_list(:geo_lfs_object_registry, 3, :synced)

      service.execute

      expect(registries.map { |registry| registry.reload.blob_path }).to eq(registries.map { |r| expected_path(r) })
    end

    context 'with an upload registry' do
      let(:replicator_class) { Geo::ProjectUploadReplicator }
      let(:registry_class) { Geo::ProjectUploadRegistry }

      it 'fills the blob path and the uploader class' do
        registry = create(:geo_project_upload_registry, :synced)
        upload = registry.project_upload

        service.execute

        expect(registry.reload).to have_attributes(
          blob_path: upload.retrieve_uploader.relative_path.to_s,
          uploader_class: upload.retrieve_uploader.class.to_s
        )
        expect(registry.blob_path).to be_present
      end
    end

    it 'skips registries that are not synced' do
      pending_registry = create(:geo_lfs_object_registry)
      failed_registry = create(:geo_lfs_object_registry, :failed)
      started_registry = create(:geo_lfs_object_registry, :started)

      service.execute

      expect([pending_registry, failed_registry, started_registry].map { |r| r.reload.blob_path }).to all(be_nil)
    end

    it 'keeps the blob path of registries that already have one' do
      registry = create(:geo_lfs_object_registry, :synced, blob_path: 'existing/path')

      service.execute

      expect(registry.reload.blob_path).to eq('existing/path')
    end

    it 'skips registries whose model is gone' do
      gone = create(:geo_lfs_object_registry, :synced)
      present = create(:geo_lfs_object_registry, :synced)
      LfsObject.where(id: gone.lfs_object_id).delete_all

      expect { service.execute }.not_to raise_error

      expect(gone.reload.blob_path).to be_nil
      expect(present.reload.blob_path).to eq(expected_path(present))
    end

    it 'does not update anything when no registry in the range has a usable location' do
      registry = create(:geo_lfs_object_registry, :synced)
      LfsObject.where(id: registry.lfs_object_id).delete_all

      expect(registry_class).to receive(:fill_missing_blob_locations).with([]).and_call_original

      service.execute

      expect(registry.reload.blob_path).to be_nil
    end

    it 'leaves a path over 1024 characters empty and still fills the others' do
      long = create(:geo_lfs_object_registry, :synced)
      short = create(:geo_lfs_object_registry, :synced)

      allow_next_instance_of(replicator_class) do |replicator|
        allow(replicator).to receive(:deleted_params).and_wrap_original do |original|
          params = original.call
          params[:model_record_id] == long.lfs_object_id ? params.merge(blob_path: 'a' * 1025) : params
        end
      end

      service.execute

      expect(long.reload.blob_path).to be_nil
      expect(short.reload.blob_path).to eq(expected_path(short))
    end

    it 'does not overwrite a value written after the rows were selected' do
      registry = create(:geo_lfs_object_registry, :synced)

      allow_next_instance_of(replicator_class) do |replicator|
        allow(replicator).to receive(:registry_blob_location).and_wrap_original do |original|
          registry_class.where(id: registry.id).update_all(blob_path: 'fresh/from/resync')
          original.call
        end
      end

      service.execute

      expect(registry.reload.blob_path).to eq('fresh/from/resync')
    end

    it 'marks the replicator done once a claimed range is past the highest registry ID' do
      create(:geo_lfs_object_registry, :synced)

      service.execute
      expect(cursor).not_to be_done

      expect(Gitlab::Geo::Logger).to receive(:info).with(
        hash_including(message: 'Registry blob location backfill complete', replicable_name: 'lfs_object')
      )

      service.execute

      expect(cursor).to be_done
    end

    it 'marks an empty table done on the first call' do
      service.execute

      expect(cursor).to be_done
    end

    it 'does nothing once done' do
      cursor.mark_done!
      registry = create(:geo_lfs_object_registry, :synced)

      service.execute

      expect(registry.reload.blob_path).to be_nil
    end

    it 'only processes registries in the claimed ID range' do
      inside = create(:geo_lfs_object_registry, :synced)
      outside = create(:geo_lfs_object_registry, :synced)

      described_class.new(replicator_class, batch_size: 1).tap do |small_batch|
        cursor.claim_range(inside.id - 1) # position the cursor just before the first row
        small_batch.execute
      end

      expect(inside.reload.blob_path).to be_present
      expect(outside.reload.blob_path).to be_nil
    end

    it 'processes a claimed range that starts at the highest registry ID' do
      registry = create(:geo_lfs_object_registry, :synced)
      cursor.claim_range(registry.id - 1) # the next claimed range starts at the highest ID

      described_class.new(replicator_class, batch_size: 1).execute

      expect(registry.reload.blob_path).to be_present
      expect(cursor).not_to be_done
    end

    it 'does not advance the cursor when reading the highest registry ID fails' do
      create(:geo_lfs_object_registry, :synced)
      allow(registry_class).to receive(:maximum).and_raise(ActiveRecord::StatementInvalid, 'boom')

      expect { service.execute }.to raise_error(ActiveRecord::StatementInvalid, 'boom')

      expect(cursor.position).to eq(0)
    end

    it 'logs the claimed range and re-raises when a batch fails' do
      create(:geo_lfs_object_registry, :synced)
      allow(registry_class).to receive(:fill_missing_blob_locations)
        .and_raise(ActiveRecord::StatementInvalid, 'boom')

      expect(Gitlab::Geo::Logger).to receive(:error).with(
        hash_including(
          message: 'Registry blob location backfill batch failed', replicable_name: 'lfs_object',
          first_id: cursor.position + 1, last_id: cursor.position + batch_size
        )
      )

      expect { service.execute }.to raise_error(ActiveRecord::StatementInvalid, 'boom')
    end

    it 'logs one debug line per batch' do
      create(:geo_lfs_object_registry, :synced)

      expect(Gitlab::Geo::Logger).to receive(:debug).with(
        hash_including(message: 'Registry blob location backfill batch', replicable_name: 'lfs_object',
          updated_count: 1)
      )

      service.execute
    end
  end

  describe 'query count' do
    # A batch handles every synced registry in range, so the other registries are made
    # failed to get a one-registry run.
    def count_queries(registries, synced_registries)
      redis_shared_state_cleanup!
      registry_class.where(id: registries.map(&:id))
        .update_all(blob_path: nil, state: registry_class.state_value(:failed))
      registry_class.where(id: synced_registries.map(&:id)).update_all(state: registry_class.state_value(:synced))

      ActiveRecord::QueryRecorder.new { service.execute }.count
    end

    shared_examples 'a backfill with a constant number of queries' do
      it 'does not run more queries for 3 registries than for 1' do
        registries = create_list(registry_factory, 3, :synced)

        count_queries(registries, registries.first(1)) # warm up
        one = count_queries(registries, registries.first(1))
        three = count_queries(registries, registries)

        expect(three).to eq(one)
        expect(registries.map { |registry| registry.reload.blob_path }).to all(be_present)
      end
    end

    context 'with project uploads' do
      let(:replicator_class) { Geo::ProjectUploadReplicator }
      let(:registry_class) { Geo::ProjectUploadRegistry }
      let(:registry_factory) { :geo_project_upload_registry }

      it_behaves_like 'a backfill with a constant number of queries'
    end

    context 'with Terraform state versions' do
      let(:replicator_class) { Geo::TerraformStateVersionReplicator }
      let(:registry_class) { Geo::TerraformStateVersionRegistry }
      let(:registry_factory) { :geo_terraform_state_version_registry }

      it_behaves_like 'a backfill with a constant number of queries'
    end

    context 'with job artifacts' do
      let(:replicator_class) { Geo::JobArtifactReplicator }
      let(:registry_class) { Geo::JobArtifactRegistry }
      let(:registry_factory) { :geo_job_artifact_registry }

      it_behaves_like 'a backfill with a constant number of queries'
    end
  end
end
