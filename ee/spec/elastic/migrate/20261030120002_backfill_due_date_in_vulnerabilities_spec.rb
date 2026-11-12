# frozen_string_literal: true

require 'spec_helper'
require File.expand_path('ee/elastic/migrate/20261030120002_backfill_due_date_in_vulnerabilities.rb')

RSpec.describe BackfillDueDateInVulnerabilities, :elastic, feature_category: :vulnerability_management do
  let(:version) { 20261030120002 }
  let(:migration) { described_class.new(version) }

  before do
    stub_ee_application_setting(elasticsearch_search: true, elasticsearch_indexing: true)
    set_elasticsearch_migration_to(version, including: false)
  end

  describe 'migration_options' do
    it 'has migration options set', :aggregate_failures do
      expect(migration).to be_batched
      expect(migration.throttle_delay).to eq(30.seconds)
      expect(migration.batch_size).to eq(30_000)
    end
  end

  describe '.migrate' do
    let_it_be(:reads_with_due_date) do
      create_list(:vulnerability_read, 2).each do |read|
        create(:vulnerability_finding_due_date, finding: read.vulnerability_occurrence)
      end
    end

    let_it_be(:read_without_due_date) { create(:vulnerability_read) }

    subject(:migrate) { migration.migrate }

    before do
      migration.set_migration_state(current_id: 0)
    end

    it_behaves_like 'it syncs vulnerabilities with ES', -> { reads_with_due_date.map(&:id) }, :migrate

    it 'resumes after the last processed finding on the next run' do
      allow(migration).to receive_messages(batch_size: 1, limit_per_iteration: 1)
      finding_ids = reads_with_due_date.map(&:vulnerability_occurrence_id).sort

      migration.migrate
      expect(migration.migration_state[:current_id]).to eq(finding_ids.first)
      expect(migration).not_to be_completed

      migration.migrate
      expect(migration.migration_state[:current_id]).to eq(finding_ids.last)
      expect(migration).to be_completed
    end
  end

  describe '.completed?' do
    context 'when there are vulnerability reads with a due date to process' do
      let_it_be(:read_with_due_date) { create(:vulnerability_read) }

      before_all do
        create(:vulnerability_finding_due_date, finding: read_with_due_date.vulnerability_occurrence)
      end

      it 'returns false' do
        expect(migration).not_to be_completed
      end

      context 'when they have all been processed' do
        before do
          migration.set_migration_state(current_id: read_with_due_date.vulnerability_occurrence_id)
        end

        it 'returns true' do
          expect(migration).to be_completed
        end
      end
    end

    context 'when no vulnerability reads have a due date' do
      let_it_be(:read_without_due_date) { create(:vulnerability_read) }

      it 'returns true' do
        expect(migration).to be_completed
      end
    end
  end
end
