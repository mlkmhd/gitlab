# frozen_string_literal: true

require 'spec_helper'
require_migration!

RSpec.describe AddAuthzRefreshTriggersToGroupGroupLinks, migration: :gitlab_main_org, feature_category: :permissions do
  let(:organizations) { table(:organizations) }
  let(:users) { table(:users) }
  let(:namespaces) { table(:namespaces) }
  let(:members) { table(:members) }
  let(:links) { table(:group_group_links) }
  let(:events) { table(:authz_refresh_events) }

  let(:organization) { organizations.create!(name: 'org', path: 'org') }
  let(:shared_group) { create_group('shared') }
  let(:invited_group) { create_group('invited') }
  let(:other_group) { create_group('other') }
  let(:user) { create_user('user') }
  let(:other_user) { create_user('other-user') }

  def create_group(path)
    namespaces.create!(name: path, path: path, type: 'Group', organization_id: organization.id)
  end

  def create_user(username)
    users.create!(email: "#{username}@example.com", username: username, projects_limit: 10,
      organization_id: organization.id)
  end

  def add_member(user, group, **attributes)
    members.create!(source_type: 'Namespace', source_id: group.id, member_namespace_id: group.id,
      type: 'GroupMember', user_id: user.id, access_level: Gitlab::Access::DEVELOPER,
      notification_level: NotificationSetting.levels[:global], **attributes)
  end

  def link_attributes(shared, invited)
    { shared_group_id: shared.id, shared_with_group_id: invited.id, group_access: Gitlab::Access::DEVELOPER }
  end

  def queued(target_type)
    events.where(target_type: described_class.const_get(target_type, false)).pluck(:target_id, :scope_id)
  end

  def remove_link(link)
    events.delete_all
    link.delete
  end

  describe '#up' do
    before do
      migrate!
    end

    it 'queues a share change when a group is shared with another' do
      links.create!(link_attributes(shared_group, invited_group))

      expect(queued(:GROUP_GROUP_LINK)).to contain_exactly([invited_group.id, shared_group.id])
      expect(queued(:USER_IN_GROUP)).to be_empty
    end

    it 'queues each pair once when shares are added in one statement' do
      links.insert_all([link_attributes(shared_group, invited_group), link_attributes(other_group, invited_group)])

      expect(queued(:GROUP_GROUP_LINK))
        .to contain_exactly([invited_group.id, shared_group.id], [invited_group.id, other_group.id])
    end

    context 'when a share is removed' do
      let!(:link) { links.create!(link_attributes(shared_group, invited_group)) }

      it "captures the invited group's members on the shared group, and queues a share change" do
        add_member(user, invited_group)

        remove_link(link)

        expect(queued(:USER_IN_GROUP)).to contain_exactly([user.id, shared_group.id])
        expect(queued(:GROUP_GROUP_LINK)).to contain_exactly([invited_group.id, shared_group.id])
      end

      it 'makes the captured events ready at once' do
        add_member(user, invited_group)

        remove_link(link)

        expect(events.where(target_type: described_class::USER_IN_GROUP).first.visible_at).to be_nil
      end

      it 'captures a user whose membership event for the invited group is still queued' do
        events.create!(
          target_type: described_class::USER_IN_GROUP, target_id: other_user.id, scope_id: invited_group.id
        )
        link.delete

        expect(queued(:USER_IN_GROUP)).to include([other_user.id, shared_group.id])
      end

      it 'captures no members that grant no access' do
        add_member(user, invited_group, access_level: Gitlab::Access::MINIMAL_ACCESS)
        add_member(other_user, invited_group, requested_at: Time.current)

        remove_link(link)

        expect(queued(:USER_IN_GROUP)).to be_empty
      end

      it 'queues the shared group for all its users when the invited group is deleted' do
        add_member(user, invited_group)
        events.delete_all

        namespaces.where(id: invited_group.id).delete_all

        expect(links.count).to eq(0)
        expect(queued(:NAMESPACE_SUBTREE)).to contain_exactly([shared_group.id, nil])
      end

      it 'queues no full recalculation when the invited group still exists' do
        add_member(user, invited_group)

        remove_link(link)

        expect(queued(:NAMESPACE_SUBTREE)).to be_empty
      end

      it 'queues nothing for a deleted shared group' do
        add_member(user, invited_group)
        events.delete_all

        namespaces.where(id: shared_group.id).delete_all

        expect(links.count).to eq(0)
        expect(events.where(scope_id: shared_group.id).count).to eq(0)
      end

      it 'queues the shared group for all its users instead, above the capture limit' do
        stub_const("#{described_class}::CAPTURE_LIMIT", 1)
        schema_migrate_down!
        migrate!
        add_member(user, invited_group)
        add_member(other_user, invited_group)

        remove_link(link)

        expect(queued(:NAMESPACE_SUBTREE)).to contain_exactly([shared_group.id, nil])
        expect(queued(:USER_IN_GROUP)).to be_empty
      end
    end

    it 'queues a share change when the access of a share changes' do
      link = links.create!(link_attributes(shared_group, invited_group))
      events.delete_all

      link.update!(group_access: Gitlab::Access::MAINTAINER)

      expect(queued(:GROUP_GROUP_LINK)).to contain_exactly([invited_group.id, shared_group.id])
      expect(queued(:USER_IN_GROUP)).to be_empty
    end

    it "captures the old pair's members and queues the new pair when a share is repointed" do
      link = links.create!(link_attributes(shared_group, invited_group))
      add_member(user, invited_group)
      events.delete_all

      link.update!(shared_group_id: other_group.id)

      expect(queued(:USER_IN_GROUP)).to contain_exactly([user.id, shared_group.id])
      expect(queued(:GROUP_GROUP_LINK))
        .to contain_exactly([invited_group.id, shared_group.id], [invited_group.id, other_group.id])
    end

    it 'queues nothing when a column that grants no access changes' do
      link = links.create!(link_attributes(shared_group, invited_group))
      events.delete_all

      link.update!(expires_at: 1.week.from_now)

      expect(events.count).to eq(0)
    end
  end

  describe '#down' do
    it 'stops queueing' do
      migrate!
      schema_migrate_down!

      links.create!(link_attributes(shared_group, invited_group))

      expect(events.count).to eq(0)
    end
  end
end
