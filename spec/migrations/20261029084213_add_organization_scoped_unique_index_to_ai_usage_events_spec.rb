# frozen_string_literal: true

require 'spec_helper'
require_migration!

RSpec.describe AddOrganizationScopedUniqueIndexToAiUsageEvents, feature_category: :value_stream_management do
  let(:connection) { ApplicationRecord.connection }
  let(:index_name) { described_class::INDEX_NAME }

  def index_flags(name)
    connection.select_one(<<~SQL)
      SELECT x.indisunique AS unique, x.indnullsnotdistinct AS nulls_not_distinct
      FROM pg_index x JOIN pg_class c ON c.oid = x.indexrelid
      WHERE c.relname = #{connection.quote(name)}
    SQL
  end

  def partition_index_count
    connection.select_value(<<~SQL)
      SELECT count(*) FROM pg_inherits i JOIN pg_class p ON p.oid = i.inhparent
      WHERE p.relname = #{connection.quote(index_name)}
    SQL
  end

  it 'adds an organization-scoped unique index on the parent and every partition' do
    partitions = Gitlab::Database::PostgresPartition.for_parent_table(:ai_usage_events).count

    reversible_migration do |migration|
      migration.before -> {
        expect(index_flags(index_name)).to be_nil
      }

      migration.after -> {
        expect(connection.index_exists?(:ai_usage_events,
          %i[namespace_id user_id event timestamp organization_id], name: index_name, unique: true)).to be(true)
        expect(index_flags(index_name)).to eq('unique' => true, 'nulls_not_distinct' => true)
        expect(partition_index_count).to eq(partitions)
      }
    end
  end
end
