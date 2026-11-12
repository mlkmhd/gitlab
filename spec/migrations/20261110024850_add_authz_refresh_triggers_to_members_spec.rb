# frozen_string_literal: true

require 'spec_helper'
require_migration!

RSpec.describe AddAuthzRefreshTriggersToMembers, migration: :gitlab_main_org, feature_category: :permissions do
  let(:organizations) { table(:organizations) }
  let(:users) { table(:users) }
  let(:namespaces) { table(:namespaces) }
  let(:projects) { table(:projects) }
  let(:members) { table(:members) }
  # Only member events: the earlier projects and namespaces triggers also queue events when the spec creates them.
  let(:events) do
    table(:authz_refresh_events).where(target_type: [described_class::USER_IN_PROJECT, described_class::USER_IN_GROUP])
  end

  let(:organization) { organizations.create!(name: 'org', path: 'org') }
  let(:group) { namespaces.create!(name: 'group', path: 'group', type: 'Group', organization_id: organization.id) }
  let(:project) do
    project_namespace = namespaces.create!(name: 'project', path: 'project', type: 'Project',
      organization_id: organization.id)

    projects.create!(name: 'project', path: 'project', namespace_id: group.id,
      project_namespace_id: project_namespace.id, organization_id: organization.id)
  end

  let(:user) { create_user('user') }
  let(:other_user) { create_user('other-user') }

  def create_user(username)
    users.create!(email: "#{username}@example.com", username: username, projects_limit: 10,
      organization_id: organization.id)
  end

  def project_member_attributes(user, **attributes)
    { source_type: 'Project', source_id: project.id, member_namespace_id: project.project_namespace_id,
      type: 'ProjectMember', user_id: user&.id, access_level: Gitlab::Access::DEVELOPER,
      notification_level: NotificationSetting.levels[:global], **attributes }
  end

  def group_member_attributes(user, **attributes)
    { source_type: 'Namespace', source_id: group.id, member_namespace_id: group.id,
      type: 'GroupMember', user_id: user&.id, access_level: Gitlab::Access::DEVELOPER,
      notification_level: NotificationSetting.levels[:global], **attributes }
  end

  def invite_attributes
    project_member_attributes(nil, invite_email: 'invite@example.com', invite_token: 'token')
  end

  def queued_on_projects
    events.where(target_type: described_class::USER_IN_PROJECT).pluck(:target_id, :scope_id)
  end

  def queued_on_groups
    events.where(target_type: described_class::USER_IN_GROUP).pluck(:target_id, :scope_id)
  end

  describe '#up' do
    before do
      migrate!
    end

    it 'queues the user on the project when a project member is added' do
      members.create!(project_member_attributes(user))

      expect(queued_on_projects).to contain_exactly([user.id, project.id])
      expect(queued_on_groups).to be_empty
    end

    it 'queues the user on the group when a group member is added' do
      members.create!(group_member_attributes(user))

      expect(queued_on_groups).to contain_exactly([user.id, group.id])
      expect(queued_on_projects).to be_empty
    end

    it 'queues every member added in one statement' do
      members.insert_all([project_member_attributes(user), project_member_attributes(other_user)])

      expect(queued_on_projects).to contain_exactly([user.id, project.id], [other_user.id, project.id])
    end

    it 'makes the event ready at once' do
      members.create!(project_member_attributes(user))

      expect(events.first.visible_at).to be_nil
    end

    it 'queues nothing for a pending invite' do
      members.create!(invite_attributes)

      expect(events.count).to eq(0)
    end

    it 'queues nothing for an access request' do
      members.create!(project_member_attributes(user, requested_at: Time.current))

      expect(events.count).to eq(0)
    end

    it 'queues nothing for a Minimal Access member' do
      members.create!(group_member_attributes(user, access_level: Gitlab::Access::MINIMAL_ACCESS))

      expect(events.count).to eq(0)
    end

    it 'queues nothing for an awaiting member' do
      members.create!(project_member_attributes(user, state: Member::STATE_AWAITING))

      expect(events.count).to eq(0)
    end

    it 'queues the user when a member is removed' do
      member = members.create!(project_member_attributes(user))
      events.delete_all

      member.delete

      expect(queued_on_projects).to contain_exactly([user.id, project.id])
    end

    it "queues nothing for members deleted with their project's namespace" do
      members.create!(project_member_attributes(user))
      events.delete_all

      namespaces.where(id: project.project_namespace_id).delete_all

      expect(members.count).to eq(0)
      expect(events.count).to eq(0)
    end

    it 'queues nothing for the memberships of a deleted user' do
      members.create!(project_member_attributes(user))
      events.delete_all

      # The loose foreign key cleanup removes the memberships after the user row is gone.
      users.where(id: user.id).delete_all
      members.where(user_id: user.id).delete_all

      expect(events.count).to eq(0)
    end

    it 'queues members deleted with their group, so removing its shares can still capture them' do
      members.create!(group_member_attributes(user))
      events.delete_all

      namespaces.where(id: group.id).delete_all

      expect(members.count).to eq(0)
      expect(queued_on_groups).to contain_exactly([user.id, group.id])
    end

    it 'queues the user once when the access level of a member changes' do
      member = members.create!(project_member_attributes(user))
      events.delete_all

      member.update!(access_level: Gitlab::Access::MAINTAINER)

      expect(queued_on_projects).to contain_exactly([user.id, project.id])
    end

    it 'queues the user when a member is reduced to Minimal Access' do
      member = members.create!(group_member_attributes(user))
      events.delete_all

      member.update!(access_level: Gitlab::Access::MINIMAL_ACCESS)

      expect(queued_on_groups).to contain_exactly([user.id, group.id])
    end

    it 'queues nothing when the access level of an access request changes' do
      member = members.create!(project_member_attributes(user, requested_at: Time.current))

      member.update!(access_level: Gitlab::Access::MAINTAINER)

      expect(events.count).to eq(0)
    end

    it 'queues the user when their access request is accepted' do
      member = members.create!(group_member_attributes(user, requested_at: Time.current))

      member.update!(requested_at: nil)

      expect(queued_on_groups).to contain_exactly([user.id, group.id])
    end

    it 'queues the user when an awaiting member is activated' do
      member = members.create!(project_member_attributes(user, state: Member::STATE_AWAITING))

      member.update!(state: described_class::STATE_ACTIVE)

      expect(queued_on_projects).to contain_exactly([user.id, project.id])
    end

    it 'queues the user when they accept an invite' do
      member = members.create!(invite_attributes)

      member.update!(user_id: user.id, invite_token: nil)

      expect(queued_on_projects).to contain_exactly([user.id, project.id])
    end

    it 'queues both users when a membership is reassigned' do
      member = members.create!(project_member_attributes(user))
      events.delete_all

      member.update!(user_id: other_user.id)

      expect(queued_on_projects).to contain_exactly([user.id, project.id], [other_user.id, project.id])
    end

    it 'queues nothing when a column that does not affect access changes' do
      member = members.create!(project_member_attributes(user))
      events.delete_all

      member.update!(notification_level: NotificationSetting.levels[:watch])

      expect(events.count).to eq(0)
    end
  end

  describe '#down' do
    it 'stops queueing' do
      migrate!
      schema_migrate_down!

      members.create!(project_member_attributes(user))

      expect(events.count).to eq(0)
    end
  end
end
