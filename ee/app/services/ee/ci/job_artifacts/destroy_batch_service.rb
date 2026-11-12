# frozen_string_literal: true

module EE
  module Ci
    module JobArtifacts
      module DestroyBatchService
        extend ::Gitlab::Utils::Override

        private

        override :destroy_around_hook
        def destroy_around_hook(artifacts)
          return yield unless ::Geo::EventStore.can_create_event?

          artifact_params = artifacts.map do |artifact|
            artifact.replicator.deleted_params
          end

          yield

          Sidekiq::Worker.skipping_transaction_check do
            ::Geo::JobArtifactReplicator.bulk_create_delete_events_async(artifact_params)
          end
        end

        override :after_batch_destroy_hook
        def after_batch_destroy_hook(artifacts)
          return if skip_publishing_deleted_event?(artifacts)

          # This DestroyBatchService is used from different services.
          # One of them is when pipeline is destroyed, and then eventually call DestroyBatchService via DestroyAssociationsService.
          # So in this case even if it is invoked after a transaction but it is still under Ci::Pipeline.transaction.
          Sidekiq::Worker.skipping_transaction_check do
            ::Gitlab::EventStore.publish(
              ::Ci::JobArtifactsDeletedEvent.new(data: { job_ids: artifacts.map(&:job_id) })
            )
          end
        end

        # When the jobs are destroyed too, loose foreign keys delete their security scans, so the
        # event would only purge scans that are deleted anyway. The batch then comes from one
        # pipeline or one project, so the first artifact's preloaded project is a stable actor.
        def skip_publishing_deleted_event?(artifacts)
          jobs_destroyed &&
            ::Feature.enabled?(:skip_job_artifacts_deleted_event_on_destroy, artifacts.first.project)
        end
      end
    end
  end
end
