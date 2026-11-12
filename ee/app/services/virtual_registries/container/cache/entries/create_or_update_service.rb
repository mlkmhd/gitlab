# frozen_string_literal: true

module VirtualRegistries
  module Container
    module Cache
      module Entries
        class CreateOrUpdateService < BaseCreateOrUpdateCacheEntriesService
          extend ::Gitlab::Utils::Override

          override :entry_class
          def entry_class
            ::VirtualRegistries::Container::Cache::Remote::Entry
          end

          private

          override :skip_md5?
          def skip_md5?
            true
          end

          override :existing_entry_response
          def existing_entry_response
            return unless deduplicatable_request? && existing_cache_entry_by_digest

            if Feature.enabled?(:container_virtual_registry_cache_revalidation_fixes, upstream.group)
              # Digest-addressed content never changes, so the entry is as fresh as the upload.
              # A tag entry with this digest is not: the tag may point elsewhere upstream now.
              if existing_cache_entry_by_digest.digest_addressed?
                existing_cache_entry_by_digest.update_column(:upstream_checked_at, Time.current)
              end

              delete_unused_upload
            end

            existing_cache_entry_by_digest.bump_downloads_count
            ServiceResponse.success(payload: { cache_entry: existing_cache_entry_by_digest })
          end

          # Workhorse uploaded to a new final path that no entry references, and authorize registered it
          # as a pending direct upload. Delete both, or they wait for the stale upload cleanup.
          def delete_unused_upload
            location = ::VirtualRegistries::Cache::EntryUploader.storage_location_identifier
            path = file.remote_id
            return if path.blank? || !::ObjectStorage::PendingDirectUpload.exists?(location, path) # rubocop:disable CodeReuse/ActiveRecord -- Redis lookup, not ActiveRecord

            ::ObjectStorage::PendingDirectUpload.new(
              redis_key: ::ObjectStorage::PendingDirectUpload.redis_key(location, path),
              storage_location_identifier: location,
              object_storage_path: path,
              timestamp: Time.current.to_i
            ).delete
          rescue StandardError => error
            # The pull already succeeded; the stale upload cleanup removes what is left.
            Gitlab::ErrorTracking.track_exception(
              error,
              upstream_id: upstream.id,
              group_id: upstream.group_id,
              class: self.class.name
            )
          end

          override :customize_updates
          def customize_updates(updates)
            updates[:digest] = digest if digest.present?
          end

          def digest
            VirtualRegistries::Container.extract_digest_from_path(path) ||
              manifest_content_digest ||
              extract_digest_from_etag(etag)
          end
          strong_memoize_attr :digest

          # Some upstreams (e.g. quay.io) send no ETag, or one that isn't the digest.
          # A manifest's digest is the sha256 of its bytes, which Workhorse computes on upload.
          def manifest_content_digest
            return unless path.include?('/manifests/') && file.sha256.present?

            "sha256:#{file.sha256}"
          end

          def extract_digest_from_etag(value)
            return if value.blank?

            value if value.match?(VirtualRegistries::Container::OCI_DIGEST_VALIDATION_REGEX)
          end

          def deduplicatable_request?
            path.include?('/blobs/') || manifest_digest_request?
          end

          def manifest_digest_request?
            path.include?('/manifests/') &&
              VirtualRegistries::Container.extract_digest_from_path(path).present?
          end

          def existing_cache_entry_by_digest
            return unless digest.present?

            ::VirtualRegistries::Container::Cache::Remote::Entry
              .default
              .for_upstream(upstream)
              .for_group(upstream.group)
              .for_digest(digest)
              .first
          end
          strong_memoize_attr :existing_cache_entry_by_digest
        end
      end
    end
  end
end
