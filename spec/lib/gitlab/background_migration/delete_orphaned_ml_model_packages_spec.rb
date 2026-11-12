# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Gitlab::BackgroundMigration::DeleteOrphanedMlModelPackages, feature_category: :mlops do
  let(:organizations) { table(:organizations) }
  let(:namespaces) { table(:namespaces) }
  let(:projects) { table(:projects) }
  let(:packages) { table(:packages_packages) }
  let(:package_files) { table(:packages_package_files) }
  let(:ml_models) { table(:ml_models) }
  let(:ml_model_versions) { table(:ml_model_versions) }
  let(:ml_experiments) { table(:ml_experiments) }
  let(:ml_candidates) { table(:ml_candidates) }

  let(:organization) { organizations.create!(name: 'Org', path: 'org') }
  let(:group_namespace) { namespaces.create!(name: 'Group', path: 'group', organization_id: organization.id) }
  let(:project_namespace) do
    namespaces.create!(name: 'Project NS', path: 'project-ns', organization_id: organization.id)
  end

  let(:project) do
    projects.create!(namespace_id: group_namespace.id, project_namespace_id: project_namespace.id,
      organization_id: organization.id)
  end

  let!(:orphan) { create_package }
  let!(:orphan_with_candidate) { create_package }
  let!(:candidate) { create_candidate(orphan_with_candidate) }
  let!(:package_with_file) { create_package.tap { |package| create_package_file(package) } }
  let!(:package_with_version) { create_package.tap { |package| create_model_version(package) } }
  let!(:live_package) { create_package(status: 0) }
  let!(:generic_package) { create_package(package_type: 7) }
  let!(:second_orphan) { create_package }

  describe '#perform' do
    subject(:perform_migration) do
      described_class.new(
        start_cursor: [packages.minimum(:id)],
        end_cursor: [end_id],
        batch_table: :packages_packages,
        batch_column: :id,
        sub_batch_size: 2,
        pause_ms: 0,
        connection: ApplicationRecord.connection
      ).perform
    end

    let(:end_id) { packages.maximum(:id) }

    it 'deletes only the orphaned ml_model packages', :aggregate_failures do
      expect { perform_migration }.to change { packages.count }.by(-3)

      expect(packages.where(id: [orphan.id, orphan_with_candidate.id, second_orphan.id])).not_to exist
      expect(packages.where(id: [package_with_file.id, package_with_version.id, live_package.id,
        generic_package.id])).to exist
    end

    it 'keeps the candidate and clears its package reference' do
      perform_migration

      expect(candidate.reload.package_id).to be_nil
    end

    it 'locks the orphans before it deletes them, in one transaction' do
      recorder = ActiveRecord::QueryRecorder.new { perform_migration }
      statements = recorder.log.grep(/\A(BEGIN|COMMIT)|FOR UPDATE SKIP LOCKED|\ADELETE FROM "packages_packages"/)

      expect(statements.first(4)).to match([
        a_string_starting_with('BEGIN'),
        a_string_including('FOR UPDATE SKIP LOCKED'),
        a_string_starting_with('DELETE FROM "packages_packages"'),
        a_string_starting_with('COMMIT')
      ])
    end

    context 'when an orphan is outside the batch range' do
      let(:end_id) { orphan_with_candidate.id }

      it 'keeps it' do
        expect { perform_migration }.to change { packages.count }.by(-2)

        expect(packages.where(id: second_orphan.id)).to exist
      end
    end
  end

  def create_package(
    package_type: described_class::ML_MODEL_PACKAGE_TYPE,
    status: described_class::PENDING_DESTRUCTION_STATUS)
    packages.create!(project_id: project.id, name: 'model', version: "1.0.#{packages.count}",
      package_type: package_type, status: status)
  end

  def create_package_file(package)
    package_files.create!(package_id: package.id, project_id: project.id, file_name: 'model.bin', file: 'model.bin')
  end

  def create_model_version(package)
    model = ml_models.create!(project_id: project.id, name: 'model')

    ml_model_versions.create!(project_id: project.id, model_id: model.id, package_id: package.id, version: '1.0.0')
  end

  def create_candidate(package)
    experiment = ml_experiments.create!(project_id: project.id, iid: 1, name: 'experiment')

    ml_candidates.create!(project_id: project.id, experiment_id: experiment.id, package_id: package.id,
      eid: SecureRandom.uuid)
  end
end
