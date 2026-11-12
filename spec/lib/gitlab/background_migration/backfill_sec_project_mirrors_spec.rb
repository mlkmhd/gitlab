# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Gitlab::BackgroundMigration::BackfillSecProjectMirrors, feature_category: :organization do
  let(:organizations) { table(:organizations, database: :main, primary_key: :id) }
  let(:namespaces) { table(:namespaces, database: :main, primary_key: :id) }
  let(:projects) { table(:projects, database: :main, primary_key: :id) }
  let(:sec_project_mirrors) { table(:sec_project_mirrors, database: :sec, primary_key: :project_id) }

  let!(:organization) { organizations.create!(name: 'organization', path: 'organization') }
  let!(:other_organization) { organizations.create!(name: 'other', path: 'other') }

  let!(:group) { namespaces.create!(name: 'group', path: 'group', organization_id: organization.id) }

  let!(:project) do
    project_namespace = namespaces.create!(
      name: 'project', path: 'project', type: 'Project', organization_id: organization.id
    )

    projects.create!(
      name: 'project',
      path: 'project',
      namespace_id: group.id,
      project_namespace_id: project_namespace.id,
      organization_id: organization.id
    )
  end

  def perform_migration(sub_batch_size: 1)
    described_class.new(
      start_cursor: [projects.minimum(:id)],
      end_cursor: [projects.maximum(:id)],
      batch_table: :projects,
      batch_column: :id,
      sub_batch_size: sub_batch_size,
      pause_ms: 0,
      connection: ApplicationRecord.connection
    ).perform
  end

  describe '#perform' do
    it 'mirrors projects that have no mirror yet' do
      expect { perform_migration }.to change { sec_project_mirrors.count }.from(0).to(1)

      expect(sec_project_mirrors.find(project.id)).to have_attributes(
        namespace_id: group.id,
        organization_id: organization.id
      )
    end

    it 'refreshes mirrors that drifted from the project' do
      sec_project_mirrors.create!(
        project_id: project.id,
        namespace_id: group.id,
        organization_id: other_organization.id
      )

      perform_migration

      expect(sec_project_mirrors.find(project.id).organization_id).to eq(organization.id)
    end

    it 'writes one upsert per sub-batch rather than one per row' do
      4.times do |i|
        project_namespace = namespaces.create!(
          name: "extra#{i}", path: "extra#{i}", type: 'Project', organization_id: organization.id
        )

        projects.create!(
          name: "extra#{i}",
          path: "extra#{i}",
          namespace_id: group.id,
          project_namespace_id: project_namespace.id,
          organization_id: organization.id
        )
      end

      recorder = ActiveRecord::QueryRecorder.new { perform_migration(sub_batch_size: 2) }

      # 5 projects in sub-batches of 2 is 3 sub-batches, so a per-row upsert would log 5.
      expect(projects.count).to eq(5)
      expect(recorder.log.grep(/INSERT INTO "sec_project_mirrors"/).count).to eq(3)
    end
  end
end
