# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Ai::DuoWorkflows::TurnClaim, :clean_gitlab_redis_shared_state, feature_category: :duo_agent_platform do
  subject(:claim) { described_class.new(1) }

  it 'is obtained once until it is released', :aggregate_failures do
    expect(claim.obtain).to be(true)
    expect(described_class.new(1).obtain).to be(false)

    claim.release

    expect(described_class.new(1).obtain).to be(true)
  end

  it 'is released by any instance for the same session' do
    claim.obtain

    described_class.new(1).release

    expect(claim.obtain).to be(true)
  end

  it 'is held per session' do
    claim.obtain

    expect(described_class.new(2).obtain).to be(true)
  end

  it 'expires on its own' do
    claim.obtain

    ttl = Gitlab::Redis::SharedState.with do |redis|
      redis.ttl(Gitlab::ExclusiveLease.redis_shared_state_key('duo_workflows:turn_claim:1'))
    end

    expect(ttl).to be_within(5).of(described_class::TTL.to_i)
  end
end
