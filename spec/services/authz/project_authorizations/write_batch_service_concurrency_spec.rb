# frozen_string_literal: true

require 'spec_helper'

# Needs real concurrent connections, so it uses the :delete strategy and no let_it_be.
RSpec.describe Authz::ProjectAuthorizations::WriteBatchService, :delete, feature_category: :permissions do
  let!(:user) { create(:user) }
  let!(:other_user) { create(:user) }
  let!(:project) { create(:project) }

  let(:release) { Queue.new }
  let(:threads) { [] }

  after do
    release << true
    threads.each { |thread| thread.join(10) }
  end

  # Starts a writer for the user that holds its lock, inside its calculation, until released.
  def start_writer(user, level)
    locked = Queue.new

    threads << Thread.new do
      described_class.new(user_id: user.id).execute([project.id]) do |ids|
        locked << ProjectAuthorization.connection.select_value('SELECT pg_backend_pid()')
        release.pop(timeout: 10)
        ids.index_with(level)
      end
    end

    locked.pop(timeout: 10) || raise('the writer did not take its lock')
  end

  def in_thread(&block)
    Thread.new(&block).tap { |thread| threads << thread }
  end

  def wait_until_a_session_is_blocked_by(pid)
    Timeout.timeout(10) do
      sleep 0.01 until ApplicationRecord.connection.select_value(<<~SQL).present?
        SELECT 1 FROM pg_stat_activity WHERE pg_blocking_pids(pid) @> ARRAY[#{pid.to_i}] LIMIT 1
      SQL
    end
  end

  def stored_levels(user)
    ProjectAuthorization.stored_levels_for_user(user.id, [project.id])
  end

  it "makes wait_for_writers wait for a writer holding the user's lock, then see its rows" do
    writer_pid = start_writer(user, Gitlab::Access::DEVELOPER)

    waiter = in_thread do
      described_class.wait_for_writers([user.id])
      stored_levels(user)
    end
    wait_until_a_session_is_blocked_by(writer_pid)
    release << true

    expect(waiter.value).to eq(project.id => [Gitlab::Access::DEVELOPER])
  end

  it "makes a second writer for the same user wait, then calculate from the first writer's rows" do
    writer_pid = start_writer(user, Gitlab::Access::MAINTAINER)
    seen = Queue.new

    second = in_thread do
      described_class.new(user_id: user.id).execute([project.id]) do |ids|
        seen << stored_levels(user)
        ids.index_with(Gitlab::Access::DEVELOPER)
      end
    end
    wait_until_a_session_is_blocked_by(writer_pid)
    release << true

    expect(second.value).to have_attributes(rows_added: 1, rows_deleted: 1)
    expect(seen.pop(timeout: 10)).to eq(project.id => [Gitlab::Access::MAINTAINER])
    expect(stored_levels(user)).to eq(project.id => [Gitlab::Access::DEVELOPER])
  end

  it "doesn't make a writer for another user wait" do
    start_writer(user, Gitlab::Access::DEVELOPER)

    other = in_thread do
      described_class.new(user_id: other_user.id).execute([project.id]) do |ids|
        ids.index_with(Gitlab::Access::DEVELOPER)
      end
    end

    expect(other.join(10)).to be(other)
    # The first writer gives up waiting for its release after 10 seconds, so check it still holds its lock.
    expect(threads.first).to be_alive
    expect(other.value).to have_attributes(rows_added: 1)
  end
end
