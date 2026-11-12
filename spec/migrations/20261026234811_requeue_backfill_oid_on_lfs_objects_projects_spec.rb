# frozen_string_literal: true

require 'spec_helper'
require_migration!

RSpec.describe RequeueBackfillOidOnLfsObjectsProjects, migration: :gitlab_main_org, feature_category: :source_code_management do
  let!(:batched_migration) { described_class::MIGRATION }

  it 'schedules the batched migration', :aggregate_failures do
    reversible_migration do |migration|
      migration.before -> {
        expect(batched_migration).not_to have_scheduled_batched_migration
      }

      migration.after -> {
        expect(batched_migration).to have_scheduled_batched_migration(
          gitlab_schema: :gitlab_main_org,
          table_name: :lfs_objects_projects,
          column_name: :id,
          batch_size: described_class::BATCH_SIZE,
          sub_batch_size: described_class::SUB_BATCH_SIZE,
          interval: 2.minutes
        )
      }
    end
  end

  context 'when the finalized batched migration from the original run still exists' do
    let(:batched_background_migrations) { table(:batched_background_migrations) }

    let!(:original_run) do
      batched_background_migrations.create!(
        job_class_name: batched_migration,
        table_name: :lfs_objects_projects,
        column_name: :id,
        job_arguments: [],
        batch_size: described_class::BATCH_SIZE,
        sub_batch_size: described_class::SUB_BATCH_SIZE,
        interval: 2.minutes,
        gitlab_schema: :gitlab_main_org,
        min_value: 1,
        max_value: 2,
        status: 3 # finished
      )
    end

    it 'deletes the existing run before scheduling a new one', :aggregate_failures do
      migrate!

      expect(batched_background_migrations.where(id: original_run.id)).to be_empty

      expect(batched_migration).to have_scheduled_batched_migration(
        gitlab_schema: :gitlab_main_org,
        table_name: :lfs_objects_projects,
        column_name: :id,
        batch_size: described_class::BATCH_SIZE,
        sub_batch_size: described_class::SUB_BATCH_SIZE,
        interval: 2.minutes
      )

      schema_migrate_down!

      expect(batched_migration).not_to have_scheduled_batched_migration
    end
  end
end
