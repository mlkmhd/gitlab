# frozen_string_literal: true

module Gitlab
  module SidekiqMiddleware
    module ConcurrencyLimit
      class WorkerExecutionTracker
        include ExclusiveLeaseGuard

        TRACKING_KEY_TTL = 600.seconds
        SCOPE_SEPARATOR = '|'
        # Executing-hash field prefix for a resumed job's reserved slot, replaced when the job starts.
        RESERVATION_PREFIX = 'resumed:'

        # Lua: counts in `used` the executing-hash values in `values` that belong to scope ARGV[scope_arg].
        COUNT_SCOPE_LUA = <<~LUA.freeze
          local used = 0
          local suffix = '#{SCOPE_SEPARATOR}' .. ARGV[scope_arg]
          for _, value in ipairs(values) do
            if string.sub(value, -#suffix) == suffix then
              used = used + 1
            end
          end
        LUA

        # Admits a job, tracking it, if it holds a reservation of its scope or the worker and its scope both
        # have room. A reservation of another scope (e.g. made while the scope was off) is released first.
        # KEYS: executing hash. ARGV: field ('' outside Sidekiq), value, limit, scope key, scope limit,
        # reservation field (''). Returns 1 when the worker is at its limit, 2 when the scope is, 0 once tracked.
        TRACK_SCOPED_EXECUTION_START_SCRIPT = ::Labkit::Redis::Script.new(<<~LUA)
          if ARGV[6] ~= '' then
            local reserved = redis.call('hget', KEYS[1], ARGV[6])
            if reserved then
              redis.call('hdel', KEYS[1], ARGV[6])
              local suffix = '#{SCOPE_SEPARATOR}' .. ARGV[4]
              if ARGV[4] == '' or string.sub(reserved, -#suffix) == suffix then
                if ARGV[1] ~= '' then
                  redis.call('hset', KEYS[1], ARGV[1], ARGV[2])
                end
                return 0
              end
            end
          end

          if redis.call('hlen', KEYS[1]) >= tonumber(ARGV[3]) then
            return 1
          end

          if ARGV[4] ~= '' then
            local values = redis.call('hvals', KEYS[1])
            local scope_arg = 4
            #{COUNT_SCOPE_LUA}
            if used >= tonumber(ARGV[5]) then
              return 2
            end
          end

          if ARGV[1] ~= '' then
            redis.call('hset', KEYS[1], ARGV[1], ARGV[2])
          end
          return 0
        LUA

        # Reserves slots for resumed jobs, in order, while the worker and the scope have room.
        # KEYS: executing hash. ARGV: value, limit, scope key ('' if none), scope limit, then the jids
        # ('' for a job without one, which takes no slot). Returns how many leading jobs can be resumed.
        RESERVE_RESUMED_JOBS_SCRIPT = ::Labkit::Redis::Script.new(<<~LUA)
          local room = tonumber(ARGV[2]) - redis.call('hlen', KEYS[1])
          if ARGV[3] ~= '' then
            local values = redis.call('hvals', KEYS[1])
            local scope_arg = 3
            #{COUNT_SCOPE_LUA}
            room = math.min(room, tonumber(ARGV[4]) - used)
          end

          local accepted = 0
          for i = 5, #ARGV do
            local field = '#{RESERVATION_PREFIX}' .. ARGV[i]
            -- A job resumed again (e.g. after a crash before the queue was trimmed) keeps its slot.
            if ARGV[i] ~= '' and redis.call('hexists', KEYS[1], field) == 0 then
              if room <= 0 then
                break
              end
              redis.call('hset', KEYS[1], field, ARGV[1])
              room = room - 1
            end
            accepted = accepted + 1
          end
          return accepted
        LUA

        UNTRACK_PENDING_RESUMED_JOB_SCRIPT = ::Labkit::Redis::Script.new(<<~LUA)
          local count = redis.call('decrby', KEYS[1], ARGV[2])
          if count < 0 then
            redis.call('set', KEYS[1], 0, 'EX', ARGV[1])
            return 0
          end
          return count
        LUA

        def initialize(worker_name:, prefix:)
          @worker_name = worker_name
          @prefix = prefix
        end

        # The scope key is stored beside the start time, so per-scope counts share the stale-tracker
        # cleanup; reserved_jid is a resumed job whose reserved slot this execution takes over.
        def track_execution_start(scope_key = nil, reserved_jid: nil)
          return release_reserved_jobs([reserved_jid].compact) if sidekiq_pid.nil?

          process_thread_id = process_thread_id_key(sidekiq_pid, sidekiq_tid)
          with_redis do |r|
            next r.hset(worker_executing_hash_key, process_thread_id, tracker_value(scope_key)) unless reserved_jid

            r.multi do |transaction|
              transaction.hdel(worker_executing_hash_key, reservation_field(reserved_jid))
              transaction.hset(worker_executing_hash_key, process_thread_id, tracker_value(scope_key))
            end
          end
        end

        # Checks the worker limit and the scope's share and tracks the execution in one step, so jobs picked
        # up together cannot all pass. A resumed job whose reservation was cleaned up, or is of another scope,
        # is checked like a new one.
        # Returns :limit or :scope when the job must wait, nil when it can run.
        def track_scoped_execution_start(limit:, scope_key:, scope_limit:, reserved_jid: nil)
          process_thread_id = sidekiq_pid.nil? ? '' : process_thread_id_key(sidekiq_pid, sidekiq_tid)
          reservation = reserved_jid ? reservation_field(reserved_jid) : ''

          result = with_redis do |r|
            TRACK_SCOPED_EXECUTION_START_SCRIPT.eval(r, keys: [worker_executing_hash_key],
              argv: [process_thread_id, tracker_value(scope_key), limit, scope_key.to_s, scope_limit, reservation])
          end

          { 1 => :limit, 2 => :scope }[result]
        end

        # Reserving in the executing hash counts resumed jobs against the limit as soon as they are picked;
        # the reservation of a job that never starts goes with the stale-tracker cleanup.
        # @return [Integer] how many of the leading jids (in queue order) can be resumed
        def reserve_resumed_jobs(jids, limit:, scope_key:, scope_limit:)
          with_redis do |r|
            RESERVE_RESUMED_JOBS_SCRIPT.eval(r, keys: [worker_executing_hash_key],
              argv: [tracker_value(scope_key), limit, scope_key.to_s, scope_limit, *jids.map(&:to_s)])
          end
        end

        def release_reserved_jobs(jids)
          return if jids.empty?

          with_redis { |r| r.hdel(worker_executing_hash_key, jids.map { |jid| reservation_field(jid) }) }
        end

        def track_execution_end
          return if sidekiq_pid.nil?

          process_thread_id = process_thread_id_key(sidekiq_pid, sidekiq_tid)
          with_redis do |r|
            r.hdel(worker_executing_hash_key, process_thread_id)
          end
        end

        def cleanup_stale_trackers
          try_obtain_lease do
            executing_threads_hash = with_redis { |r| r.hgetall(worker_executing_hash_key) }
            break if executing_threads_hash.empty?

            dangling = executing_threads_hash.filter { |k, v| !still_executing?(k, v) }
            break if dangling.empty?

            with_redis do |r|
              r.hdel(worker_executing_hash_key, dangling)
            end
          end
        end

        def concurrent_worker_count
          with_redis { |r| r.hlen(worker_executing_hash_key).to_i }
        end

        # Scans the whole executing hash, like scoped admission, so a scoped worker's Redis CPU grows with
        # RPS x max limit: check that against the CPU budget before scoping a busy worker (counters per scope
        # would make it O(1)).
        # @return [Hash{String => Integer}] executing and reserved job count per scope key
        def concurrent_counts_by_scope
          values = with_redis { |r| r.hvals(worker_executing_hash_key) }
          values.filter_map { |value| value.split(SCOPE_SEPARATOR, 2)[1] }.tally
        end

        # Tracks jobs that have been resumed (enqueued for processing) but have not
        # started executing yet, so they can be counted against the concurrency limit
        # when deciding how many further jobs to resume. See QueueManager#num_jobs_to_resume.
        def track_pending_resumed_jobs(count)
          return if count <= 0

          with_redis do |r|
            r.pipelined do |pipeline|
              pipeline.incrby(pending_resumed_jobs_key, count)
              pipeline.expire(pending_resumed_jobs_key, TRACKING_KEY_TTL.to_i)
            end
          end
        end

        def untrack_pending_resumed_job(count = 1)
          return if count <= 0

          # Decrement and floor at zero atomically so a concurrent num_jobs_to_resume never
          # observes a negative intermediate value, which would inflate the resume batch.
          # The floor guards against drift (e.g. the counter expiring before the job starts).
          with_redis do |r|
            UNTRACK_PENDING_RESUMED_JOB_SCRIPT.eval(r,
              keys: [pending_resumed_jobs_key], argv: [TRACKING_KEY_TTL.to_i, count])
          end
        end

        def pending_resumed_jobs_count
          with_redis { |r| r.get(pending_resumed_jobs_key).to_i }
        end

        private

        attr_reader :worker_name

        def lease_timeout
          TRACKING_KEY_TTL
        end

        def lease_key
          "#{@prefix}:{#{worker_name.underscore}}"
        end

        def lease_release?
          false
        end

        def lease_taken_log_level
          :debug
        end

        def with_redis(&)
          Redis::QueuesMetadata.with(&) # rubocop:disable CodeReuse/ActiveRecord -- Not active record
        end

        def worker_executing_hash_key
          "#{@prefix}:{#{worker_name.underscore}}:executing"
        end

        def pending_resumed_jobs_key
          "#{@prefix}:{#{worker_name.underscore}}:pending_resumed"
        end

        def reservation_field(jid)
          "#{RESERVATION_PREFIX}#{jid}"
        end

        def tracker_value(scope_key)
          [Time.now.utc.tv_sec, scope_key].compact.join(SCOPE_SEPARATOR)
        end

        def process_thread_id_key(pid, tid)
          "#{pid}:tid:#{tid}"
        end

        def sidekiq_pid
          Gitlab::SidekiqProcess.pid
        end

        def sidekiq_tid
          Gitlab::SidekiqProcess.tid
        end

        def still_executing?(ptid, started_at)
          return true unless started_at.to_i < TRACKING_KEY_TTL.ago.utc.to_i

          pid, tid = ptid.split(":tid:")
          return false unless pid && tid

          job_hash = fetch_sidekiq_process_work_hash(pid, tid)
          return false if job_hash.empty?

          job_hash['class'] == worker_name
        end

        def fetch_sidekiq_process_work_hash(pid, tid)
          job_hash = {}
          Gitlab::SidekiqSharding::Router.route(worker_name.safe_constantize) do
            hash = Sidekiq.redis { |r| r.hget("#{pid}:work", tid) } # rubocop:disable Cop/SidekiqRedisCall -- checking process work hash
            next if hash.nil?

            # There are 2 layers of JSON encoding
            # 1. when a job is pushed into the queue -- https://github.com/sidekiq/sidekiq/blob/v7.3.9/lib/sidekiq/client.rb#L281
            # 2. When the workstate is written into the pid:work hash -- https://github.com/sidekiq/sidekiq/blob/v7.3.9/lib/sidekiq/launcher.rb#L148
            job_hash = ::Gitlab::Json.parse(::Gitlab::Json.parse(hash)&.dig('payload'))
          end

          job_hash
        rescue JSON::ParserError => e
          Gitlab::ErrorTracking.track_exception(e, worker_class: worker_name)
          {}
        end
      end
    end
  end
end
