# frozen_string_literal: true

require 'spec_helper'
require_migration!

RSpec.describe QueueDeleteOrphanedMlModelPackages, migration: :gitlab_main_org, feature_category: :mlops do
  let!(:batched_migration) { described_class::MIGRATION }

  let(:organizations) { table(:organizations) }
  let(:namespaces) { table(:namespaces) }
  let(:projects) { table(:projects) }
  let(:packages) { table(:packages_packages) }

  let(:organization) { organizations.create!(name: 'Org', path: 'org') }
  let(:group_namespace) { namespaces.create!(name: 'Group', path: 'group', organization_id: organization.id) }
  let(:project_namespace) do
    namespaces.create!(name: 'Project NS', path: 'project-ns', organization_id: organization.id)
  end

  let(:project) do
    projects.create!(namespace_id: group_namespace.id, project_namespace_id: project_namespace.id,
      organization_id: organization.id)
  end

  let!(:first_package) { create_package('1.0.0') }
  let!(:last_package) { create_package('1.0.1') }

  it 'schedules a new batched migration over packages_packages' do
    reversible_migration do |migration|
      migration.before -> {
        expect(batched_migration).not_to have_scheduled_batched_migration
      }

      migration.after -> {
        expect(batched_migration).to have_scheduled_batched_migration(
          gitlab_schema: :gitlab_main_org,
          table_name: :packages_packages,
          column_name: :id,
          batch_size: described_class::BATCH_SIZE,
          sub_batch_size: described_class::SUB_BATCH_SIZE,
          status_name: :active,
          min_cursor: [first_package.id],
          max_cursor: [last_package.id]
        )
      }
    end
  end

  def create_package(version)
    packages.create!(project_id: project.id, name: 'model', version: version, package_type: 14, status: 4)
  end
end
