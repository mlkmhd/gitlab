# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Database::ReleasePinnedConnectionLeases, feature_category: :database do
  let(:pool) { ApplicationRecord.connection_pool }

  it 'releases the pinned connection at the end of a request while the example is in a transaction' do
    expect(pool.lease_connection.pinned).to be(true)

    queried = Queue.new
    in_transaction = Queue.new
    completed = Queue.new

    request = Thread.new do
      Rails.application.executor.wrap do
        pool.lease_connection.select_value('SELECT 1')
        queried << true
        in_transaction.pop(timeout: 10)
      end
      completed << { leased: pool.active_connection? }
    ensure
      pool.release_connection
    end

    expect(queried.pop(timeout: 10)).to be(true)
    result = ApplicationRecord.transaction do
      in_transaction << true
      completed.pop(timeout: 10)
    end

    expect(request.join(10)).to be_truthy
    expect(result).to eq(leased: nil)
  end

  context 'when the connection is not pinned', :delete do
    it 'keeps the lease while a transaction is open' do
      expect(pool.lease_connection.pinned).to be(false)

      ApplicationRecord.transaction do
        connection = pool.lease_connection
        connection.select_value('SELECT 1')

        Rails.application.executor.wrap { nil }

        expect(pool.active_connection?).to equal(connection)
      end
    end
  end
end
