# frozen_string_literal: true

require 'spec_helper'
require_migration!

RSpec.describe AddAuthzRefreshTriggerToUsers, migration: :gitlab_main_org, feature_category: :permissions do
  let(:organizations) { table(:organizations) }
  let(:users) { table(:users) }
  let(:events) { table(:authz_refresh_events) }

  let(:organization) { organizations.create!(name: 'org', path: 'org') }

  def create_user(state)
    users.create!(email: 'user@example.com', username: 'user', projects_limit: 10, state: state,
      organization_id: organization.id)
  end

  def queued_users
    events.where(target_type: described_class::USER).pluck(:target_id)
  end

  describe '#up' do
    before do
      migrate!
    end

    it 'queues the user when they become active' do
      user = create_user('blocked')

      user.update!(state: 'active')

      expect(queued_users).to contain_exactly(user.id)
    end

    it 'queues nothing for an active user created or updated' do
      user = create_user('active')

      user.update!(name: 'renamed')

      expect(events.count).to eq(0)
    end

    it 'queues nothing when a user is blocked' do
      user = create_user('active')

      user.update!(state: 'blocked')

      expect(events.count).to eq(0)
    end
  end

  describe '#down' do
    it 'stops queueing' do
      migrate!
      schema_migrate_down!
      user = create_user('blocked')

      user.update!(state: 'active')

      expect(events.count).to eq(0)
    end
  end
end
