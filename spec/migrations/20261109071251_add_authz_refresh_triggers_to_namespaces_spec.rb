# frozen_string_literal: true

require 'spec_helper'
require_migration!

RSpec.describe AddAuthzRefreshTriggersToNamespaces, migration: :gitlab_main_org, feature_category: :permissions do
  let(:organizations) { table(:organizations) }
  let(:users) { table(:users) }
  let(:namespaces) { table(:namespaces) }
  let(:events) { table(:authz_refresh_events) }

  let(:organization) { organizations.create!(name: 'org', path: 'org') }
  let(:group) { create_namespace('group', type: 'Group') }
  let(:other_group) { create_namespace('other-group', type: 'Group') }

  def create_namespace(path, type:, **attributes)
    namespaces.create!(name: path, path: path, type: type, organization_id: organization.id, **attributes)
  end

  def create_user(username)
    users.create!(email: "#{username}@example.com", username: username, projects_limit: 10,
      organization_id: organization.id)
  end

  # target_type 5 is a namespace_subtree event, 6 a namespace_project_group_links event.
  def queued_subtrees
    events.where(target_type: 5).pluck(:target_id)
  end

  def queued_share_locks
    events.where(target_type: 6).pluck(:target_id)
  end

  describe '#up' do
    before do
      migrate!
    end

    it 'queues the subtree of a group moved to another parent' do
      group.update!(parent_id: other_group.id)

      expect(queued_subtrees).to contain_exactly(group.id)
      expect(queued_share_locks).to be_empty
    end

    it 'queues the subtree of a personal namespace that changes owner' do
      namespace = create_namespace('owner', type: 'User', owner_id: create_user('owner').id)

      namespace.update!(owner_id: create_user('new-owner').id)

      expect(queued_subtrees).to contain_exactly(namespace.id)
    end

    it 'queues the share lock of a group when it changes' do
      group.update!(share_with_group_lock: true)

      expect(queued_share_locks).to contain_exactly(group.id)
      expect(queued_subtrees).to be_empty
    end

    it 'queues the share lock of a personal namespace when it changes' do
      namespace = create_namespace('owner', type: 'User', owner_id: create_user('owner').id)

      namespace.update!(share_with_group_lock: true)

      expect(queued_share_locks).to contain_exactly(namespace.id)
    end

    it 'queues every descendant whose share lock one statement changes' do
      child = create_namespace('child', type: 'Group', parent_id: group.id)
      locked_child = create_namespace('locked-child', type: 'Group', parent_id: group.id, share_with_group_lock: true)
      grandchild = create_namespace('grandchild', type: 'Group', parent_id: child.id)

      namespaces.where(id: [child.id, locked_child.id, grandchild.id]).update_all(share_with_group_lock: true)

      expect(queued_share_locks).to contain_exactly(child.id, grandchild.id)
    end

    it 'queues both events when one update moves a group and changes its share lock' do
      group.update!(parent_id: other_group.id, share_with_group_lock: true)

      expect(queued_subtrees).to contain_exactly(group.id)
      expect(queued_share_locks).to contain_exactly(group.id)
    end

    it 'queues nothing for a project namespace moved with its project' do
      project_namespace = create_namespace('project', type: 'Project', parent_id: group.id)

      project_namespace.update!(parent_id: other_group.id, share_with_group_lock: true)

      expect(events.count).to eq(0)
    end

    it 'queues nothing when a column that does not affect access changes' do
      group.update!(name: 'Renamed')

      expect(events.count).to eq(0)
    end
  end

  describe '#down' do
    it 'stops queueing' do
      migrate!
      schema_migrate_down!

      group.update!(parent_id: other_group.id, share_with_group_lock: true)

      expect(events.count).to eq(0)
    end
  end
end
