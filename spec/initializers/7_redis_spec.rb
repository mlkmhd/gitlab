# frozen_string_literal: true

require 'spec_helper'

# Guards the two lines wiring redis-cloud-auth into Rails, so a refactor of
# 7_redis.rb cannot silently drop proactive re-auth.
RSpec.describe '7_redis initializer', feature_category: :redis do
  it 'registers the redis-cloud-auth re-auth middleware' do
    expect(RedisClient::Middlewares.ancestors).to include(RedisCloudAuth::ReauthMiddleware)
  end

  it 'sends re-auth failures to the application logger' do
    expect(RedisCloudAuth.logger).to eq(Gitlab::AppLogger)
  end
end
