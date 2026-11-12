# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Analytics::GroupActivityCalculator, 'database load balancing', :database_replica, :delete,
  feature_category: :value_stream_management do
  subject { described_class.new(group, current_user) }

  let!(:group) { create(:group) }
  let!(:current_user) { create(:user, developer_of: group) }

  before do
    # Start each example from a fresh session, not one that sticks after the factory writes
    ::Gitlab::Database::LoadBalancing::SessionMap.clear_session
  end

  def roles_for(pattern)
    roles = []
    callback = ->(*, payload) do
      roles << ::Gitlab::Database::LoadBalancing.db_role_for_connection(payload[:connection]) if
        payload[:sql].match?(pattern)
    end

    ActiveSupport::Notifications.subscribed(callback, 'sql.active_record') { yield }

    roles
  end

  def connections_for(pattern)
    connections = []
    callback = ->(*, payload) { connections << payload[:connection] if payload[:sql].match?(pattern) }

    ActiveSupport::Notifications.subscribed(callback, 'sql.active_record') { yield }

    connections
  end

  def count_and_timeout_roles
    timeout_roles = []
    count_roles = roles_for(/COUNT\(\*\)/) do
      timeout_roles = roles_for(/SET LOCAL statement_timeout/) { subject.merge_requests_count }
    end

    [timeout_roles, count_roles]
  end

  it 'sets the timeout and runs the count on a replica' do
    timeout_roles, count_roles = count_and_timeout_roles

    expect(timeout_roles).to eq([:replica])
    expect(count_roles).to all(eq(:replica))
    expect(count_roles).not_to be_empty
  end

  context 'when the session sticks to the primary' do
    before do
      ::Gitlab::Database::LoadBalancing::SessionMap.current(MergeRequest.load_balancer).use_primary!
    end

    it 'still sets the timeout and runs the count on a replica' do
      timeout_roles, count_roles = count_and_timeout_roles

      expect(timeout_roles).to eq([:replica])
      expect(count_roles).to all(eq(:replica))
      expect(count_roles).not_to be_empty
    end
  end

  # Three entries for the same address give three replica pools. Outside a request store every `host` call
  # moves to the next pool, and `read` calls it twice per statement, so two hosts would still line up by parity.
  context 'with three replica hosts', :request_store do
    let(:model) { ActiveRecord::Base }

    before do
      host = model.connection_db_config.configuration_hash[:host]
      configuration = ::Gitlab::Database::LoadBalancing::Configuration.new(model, [host, host, host])

      model.load_balancer.disconnect!(timeout: 0)
      model.load_balancer = ::Gitlab::Database::LoadBalancing::LoadBalancer.new(configuration)
      model.sticking = ::Gitlab::Database::LoadBalancing::Sticking.new(model.load_balancer)
      model.connection_proxy = ::Gitlab::Database::LoadBalancing::ConnectionProxy.new(model.load_balancer)
    end

    def count_and_timeout_connections
      timeout_connections = []
      count_connections = connections_for(/COUNT\(\*\)/) do
        timeout_connections = connections_for(/SET LOCAL statement_timeout/) { subject.merge_requests_count }
      end

      [timeout_connections, count_connections]
    end

    it 'runs the count on the connection that set the timeout' do
      timeout_connections, count_connections = count_and_timeout_connections

      expect(timeout_connections.size).to eq(1)
      expect(count_connections).not_to be_empty
      expect((timeout_connections + count_connections).uniq.size).to eq(1)
    end

    context 'when the session sticks to the primary' do
      before do
        ::Gitlab::Database::LoadBalancing::SessionMap.current(MergeRequest.load_balancer).use_primary!
      end

      it 'still runs the count on the connection that set the timeout' do
        timeout_connections, count_connections = count_and_timeout_connections

        expect(timeout_connections.size).to eq(1)
        expect(count_connections).not_to be_empty
        expect((timeout_connections + count_connections).uniq.size).to eq(1)
      end
    end
  end
end
