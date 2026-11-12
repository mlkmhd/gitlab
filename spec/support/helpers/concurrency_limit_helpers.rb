# frozen_string_literal: true

# Sets up the Sidekiq concurrency limiter's Redis state for a worker, as the middleware would have left it.
module ConcurrencyLimitHelpers
  def fill_executing_slots(worker_name, count)
    key = "#{Gitlab::SidekiqMiddleware::ConcurrencyLimit::ConcurrencyLimitService::REDIS_KEY_PREFIX}:" \
      "{#{worker_name.underscore}}:executing"

    Gitlab::Redis::QueuesMetadata.with do |redis|
      count.times { |i| redis.hset(key, "p:tid:#{i}", Time.now.utc.tv_sec) }
    end
  end

  def defer_job(worker_name, deferred_at: Time.now.utc, jid: 'queued')
    travel_to(deferred_at) do
      Gitlab::SidekiqMiddleware::ConcurrencyLimit::ConcurrencyLimitService
        .add_to_queue!({ 'class' => worker_name, 'args' => [], 'jid' => jid }, {})
    end
  end
end
