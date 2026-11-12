# frozen_string_literal: true

require 'spec_helper'
require_migration!

RSpec.describe CleanupRemoveDuplicateDefaultTrackedContexts,
  migration: :gitlab_main_org, feature_category: :vulnerability_management do
  let(:batched_background_migrations) { table(:batched_background_migrations) }

  context 'when the superseded batched background migration exists' do
    let!(:superseded_run) do
      batched_background_migrations.create!(
        job_class_name: described_class::MIGRATION,
        table_name: :projects,
        column_name: :id,
        job_arguments: [],
        batch_size: 10_000,
        sub_batch_size: 20,
        interval: 2.minutes,
        gitlab_schema: :gitlab_main_org,
        min_value: 1,
        max_value: 2,
        status: 4 # failed
      )
    end

    it 'deletes it' do
      expect { migrate! }.to change { batched_background_migrations.where(id: superseded_run.id).count }.from(1).to(0)
    end
  end

  context 'when the superseded batched background migration does not exist' do
    it 'does not raise' do
      expect { migrate! }.not_to raise_error
    end
  end
end
