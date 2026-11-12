# frozen_string_literal: true

require 'spec_helper'
require_migration!

RSpec.describe AddAuthzRefreshTriggersToProjectGroupLinks, migration: :gitlab_main_org,
  feature_category: :permissions do
  let(:organizations) { table(:organizations) }
  let(:namespaces) { table(:namespaces) }
  let(:projects) { table(:projects) }
  let(:links) { table(:project_group_links) }
  let(:events) { table(:authz_refresh_events) }

  let(:organization) { organizations.create!(name: 'org', path: 'org') }
  let(:group) { create_group('group') }
  let(:other_group) { create_group('other-group') }
  let(:project) { create_project('project') }
  let(:other_project) { create_project('other-project') }

  def create_group(path)
    namespaces.create!(name: path, path: path, type: 'Group', organization_id: organization.id)
  end

  def create_project(path)
    project_namespace = namespaces.create!(name: path, path: path, type: 'Project', organization_id: organization.id)

    projects.create!(name: path, path: path, namespace_id: group.id, project_namespace_id: project_namespace.id,
      organization_id: organization.id)
  end

  def link_attributes(project, group)
    { project_id: project.id, group_id: group.id, group_access: Gitlab::Access::DEVELOPER }
  end

  # target_type 1 is a project event. Nothing else writes to the table here.
  def queued_projects
    events.where(target_type: 1).pluck(:target_id)
  end

  describe '#up' do
    before do
      migrate!
    end

    it 'queues the project when a share is added' do
      links.create!(link_attributes(project, group))

      expect(queued_projects).to contain_exactly(project.id)
    end

    it 'queues the project once when shares are added in one statement' do
      links.insert_all([link_attributes(project, group), link_attributes(project, other_group)])

      expect(queued_projects).to contain_exactly(project.id)
    end

    it 'queues the project when a share is removed' do
      link = links.create!(link_attributes(project, group))
      events.delete_all

      link.delete

      expect(queued_projects).to contain_exactly(project.id)
    end

    it 'queues the project when the access level of a share changes' do
      link = links.create!(link_attributes(project, group))
      events.delete_all

      link.update!(group_access: Gitlab::Access::MAINTAINER)

      expect(queued_projects).to contain_exactly(project.id)
    end

    it 'queues both projects when a share moves to another project' do
      link = links.create!(link_attributes(project, group))
      events.delete_all

      link.update!(project_id: other_project.id)

      expect(queued_projects).to contain_exactly(project.id, other_project.id)
    end

    it 'queues nothing when a column that does not affect access changes' do
      link = links.create!(link_attributes(project, group))
      events.delete_all

      link.update!(expires_at: 1.week.from_now.to_date)

      expect(queued_projects).to be_empty
    end
  end

  describe '#down' do
    it 'stops queueing' do
      migrate!
      schema_migrate_down!

      links.create!(link_attributes(project, group))

      expect(queued_projects).to be_empty
    end
  end
end
