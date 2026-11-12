# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Gitlab::Database::OpenEndedColumns, feature_category: :database do
  describe described_class::Column do
    describe '#identifier' do
      it 'joins table and column with a dot' do
        column = described_class.new(table_name: 'users', column_name: 'bio', kind: :text)

        expect(column.identifier).to eq('users.bio')
      end
    end

    describe '#bounded_by?' do
      context 'for a text column' do
        let(:column) { described_class.new(table_name: 'users', column_name: 'bio', kind: :text) }

        it 'is bounded by a char_length check on the same column' do
          expect(column.bounded_by?('CHECK ((char_length(bio) <= 255))')).to be(true)
        end

        it 'is bounded by a char_length check on a varchar column, which PostgreSQL prints with a text cast' do
          expect(column.bounded_by?('CHECK ((char_length((bio)::text) <= 255))')).to be(true)
        end

        it 'is bounded by a length check on the same column' do
          expect(column.bounded_by?('CHECK ((length(bio) <= 255))')).to be(true)
        end

        it 'is not bounded by a check on a different column' do
          expect(column.bounded_by?('CHECK ((char_length(name) <= 255))')).to be(false)
        end

        it 'is not bounded by an unrelated check' do
          expect(column.bounded_by?('CHECK ((num_nonnulls(a, b) = 1))')).to be(false)
        end

        it 'is not bounded by a lower-bound-only check' do
          expect(column.bounded_by?('CHECK ((char_length(bio) > 0))')).to be(false)
        end

        it 'is bounded when a lower bound is combined with an upper bound' do
          expect(column.bounded_by?('CHECK (((char_length(bio) > 0) AND (char_length(bio) <= 255)))')).to be(true)
        end

        it 'is not bounded by a check on the trimmed value, because surrounding whitespace stays unbounded' do
          expect(column.bounded_by?('CHECK ((length(TRIM(BOTH FROM bio)) <= 1024))')).to be(false)
        end

        it 'is bounded by a check on a quoted reserved-word column name' do
          reserved = described_class.new(table_name: 'schedules', column_name: 'when', kind: :text)

          expect(reserved.bounded_by?('CHECK ((char_length("when") <= 255))')).to be(true)
        end
      end

      context 'for a binary column' do
        let(:column) { described_class.new(table_name: 'blobs', column_name: 'data', kind: :binary) }

        it 'is bounded by an octet_length check' do
          expect(column.bounded_by?('CHECK ((octet_length(data) <= 1048576))')).to be(true)
        end

        it 'is bounded by a fixed-size octet_length check' do
          expect(column.bounded_by?('CHECK ((octet_length(data) = 20))')).to be(true)
        end

        it 'is not bounded by a char_length check' do
          expect(column.bounded_by?('CHECK ((char_length(data) <= 100))')).to be(false)
        end

        it 'is not bounded by a non-empty check' do
          expect(column.bounded_by?('CHECK ((octet_length(data) >= 1))')).to be(false)
        end
      end

      context 'for a json column' do
        let(:column) { described_class.new(table_name: 'settings', column_name: 'payload', kind: :json) }

        it 'is bounded by an octet_length check on the text cast' do
          expect(column.bounded_by?('CHECK ((octet_length((payload)::text) <= 1024))')).to be(true)
        end

        it 'is bounded by a char_length check on the text cast' do
          expect(column.bounded_by?('CHECK ((char_length((payload)::text) <= 20000))')).to be(true)
        end

        it 'is not bounded by a jsonb_typeof shape check' do
          expect(column.bounded_by?("CHECK ((jsonb_typeof(payload) = 'object'::text))")).to be(false)
        end
      end
    end
  end

  describe '.unbounded_identifiers' do
    subject(:identifiers) { described_class.unbounded_identifiers }

    it 'returns a sorted list of table.column strings' do
      expect(identifiers).to eq(identifiers.sort)
    end

    it 'includes the description_versions.description reference case' do
      expect(identifiers).to include('description_versions.description')
    end

    it 'includes unbounded columns from tables owned by every database' do
      expect(identifiers).to include('ci_build_trace_chunks.raw_data', 'sbom_occurrences.commit_sha')
    end

    it 'includes an unbounded jsonb column' do
      expect(identifiers).to include('application_settings.oauth_provider')
    end

    it 'excludes bounded columns', :aggregate_failures do
      expect(identifiers).not_to include('p_ci_job_inputs.name')
      expect(identifiers).not_to include('packages_npm_metadata.package_json')
    end

    it 'combines and deduplicates the results of every connection' do
      main_connection = instance_double(ActiveRecord::ConnectionAdapters::PostgreSQLAdapter)
      ci_connection = instance_double(ActiveRecord::ConnectionAdapters::PostgreSQLAdapter)
      main_columns = instance_double(described_class, unbounded_identifiers: %w[users.bio schema_migrations.version])
      ci_columns = instance_double(described_class, unbounded_identifiers: %w[ci_builds.name schema_migrations.version])

      allow(Gitlab::Database::EachDatabase).to receive(:each_connection)
        .and_yield(main_connection, 'main')
        .and_yield(ci_connection, 'ci')
      allow(described_class).to receive(:new).with(main_connection).and_return(main_columns)
      allow(described_class).to receive(:new).with(ci_connection).and_return(ci_columns)

      expect(identifiers).to eq(%w[ci_builds.name schema_migrations.version users.bio])
    end
  end

  describe '#unbounded_identifiers' do
    context 'with the main connection' do
      subject(:identifiers) { described_class.new(ApplicationRecord.connection).unbounded_identifiers }

      it 'includes tables owned by main' do
        expect(identifiers).to include('description_versions.description')
      end

      it 'excludes tables owned by another database' do
        skip_if_shared_database(:ci)

        expect(identifiers).not_to include('ci_build_trace_chunks.raw_data')
      end
    end

    context 'with the ci connection' do
      subject(:identifiers) { described_class.new(Ci::ApplicationRecord.connection).unbounded_identifiers }

      it 'only includes tables owned by ci', :aggregate_failures do
        skip_if_shared_database(:ci)

        expect(identifiers).to include('ci_build_trace_chunks.raw_data')
        expect(identifiers).not_to include('description_versions.description')
      end
    end
  end
end
