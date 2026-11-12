# frozen_string_literal: true

require 'spec_helper'
require_migration!

RSpec.describe AddAuthzRefreshTriggersToProjects, migration: :gitlab_main_org, feature_category: :permissions do
  let(:organizations) { table(:organizations) }
  let(:namespaces) { table(:namespaces) }
  let(:projects) { table(:projects) }
  let(:events) { table(:authz_refresh_events) }

  let(:organization) { organizations.create!(name: 'org', path: 'org') }
  let(:group) { create_group('group') }
  let(:other_group) { create_group('other-group') }

  def create_group(path)
    namespaces.create!(name: path, path: path, type: 'Group', organization_id: organization.id)
  end

  def project_attributes(path)
    project_namespace = namespaces.create!(name: path, path: path, type: 'Project', organization_id: organization.id)

    { name: path, path: path, namespace_id: group.id, project_namespace_id: project_namespace.id,
      organization_id: organization.id }
  end

  # target_type 1 is a project event. Nothing else writes to the table here.
  def queued_projects
    events.where(target_type: 1).pluck(:target_id)
  end

  describe '#up' do
    before do
      migrate!
    end

    it 'queues a new project' do
      project = projects.create!(project_attributes('project'))

      expect(queued_projects).to contain_exactly(project.id)
    end

    it 'queues every project created in one statement' do
      projects.insert_all([project_attributes('project'), project_attributes('other-project')])

      expect(queued_projects).to match_array(projects.pluck(:id))
    end

    it 'queues a project moved to another namespace' do
      project = projects.create!(project_attributes('project'))
      events.delete_all

      project.update!(namespace_id: other_group.id)

      expect(queued_projects).to contain_exactly(project.id)
    end

    it 'queues nothing when a column that does not affect access changes' do
      project = projects.create!(project_attributes('project'))
      events.delete_all

      project.update!(name: 'Renamed')

      expect(queued_projects).to be_empty
    end
  end

  describe '#down' do
    it 'stops queueing' do
      migrate!
      schema_migrate_down!

      projects.create!(project_attributes('project'))

      expect(queued_projects).to be_empty
    end
  end
end
