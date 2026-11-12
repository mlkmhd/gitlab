# frozen_string_literal: true

# Rails keeps a request thread's lease when the request ends inside a joinable transaction, so a Puma
# thread could keep using the pinned connection after unpin, sharing it unlocked with the next example
# and crashing libpq. Releasing a pinned connection is safe: `checkin` ignores it.
unless ActiveRecord::ConnectionAdapters::ConnectionPool::ExecutorHooks.respond_to?(:complete)
  raise 'ActiveRecord::ConnectionAdapters::ConnectionPool::ExecutorHooks.complete no longer exists. ' \
    'See spec/support/database/release_pinned_connection_leases.rb'
end

module Database
  module ReleasePinnedConnectionLeases
    def complete(...)
      super

      ActiveRecord::Base.connection_handler.each_connection_pool do |pool|
        pool.release_connection if pool.active_connection?&.pinned
      end
    end
  end
end

ActiveRecord::ConnectionAdapters::ConnectionPool::ExecutorHooks.singleton_class
  .prepend(Database::ReleasePinnedConnectionLeases)
