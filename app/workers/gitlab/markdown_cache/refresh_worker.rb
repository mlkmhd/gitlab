# frozen_string_literal: true

module Gitlab
  module MarkdownCache
    class RefreshWorker # rubocop:disable Sidekiq/EnforceDatabaseHealthSignalDeferral -- picks up work that would otherwise be done synchronously
      # Deferring increases load on web instance CPU (since they have to re-render affected rows on
      # every load until the job gets to run), for almost no benefit: these jobs are ~0.2% of the
      # primary's writes, and disabling the FF means they're run *in* the web requests instead.

      include ApplicationWorker

      data_consistency :delayed
      feature_category :markdown
      urgency :low
      worker_resource_boundary :cpu
      loggable_arguments 0

      deduplicate :until_executing
      idempotent!

      concurrency_limit -> { 100 }

      def perform(class_name, id)
        klass = class_name.safe_constantize
        return unless klass

        record = klass.primary_key_in([id]).take # rubocop:disable CodeReuse/ActiveRecord -- needed here.
        return if record.nil? || record.markdown_cache_current?

        record.refresh_markdown_cache!
      end
    end
  end
end
