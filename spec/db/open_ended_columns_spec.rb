# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'Open-ended columns', feature_category: :database do
  let(:allowlist_relative_path) { 'spec/support/database/open-ended-columns-allowlist.yml' }
  let(:allowlisted_columns) { YAML.safe_load_file(Rails.root.join(allowlist_relative_path)) }
  let(:unbounded_columns) { Gitlab::Database::OpenEndedColumns.unbounded_identifiers }

  it 'requires every new open-ended column to have a size limit' do
    not_allowlisted = unbounded_columns - allowlisted_columns

    expect(not_allowlisted).to be_empty, <<~MSG
      The following open-ended column(s) were added without a size limit:

      #{not_allowlisted.map { |c| "  - #{c}" }.join("\n")}

      Unbounded columns cause uncontrolled table growth (TOAST bloat). Resolve this
      in one of these ways:

        1. For a text column, add a size limit with `add_text_limit` (or `limit:` in
           `create_table`). See
           https://docs.gitlab.com/development/database/strings_and_the_text_data_type/.
        2. For a bytea column, add an `octet_length(column) <= N` CHECK constraint.
        3. For a jsonb or json column, add an `octet_length(column::text) <= N` CHECK
           constraint.
        4. If the content is genuinely unbounded, store it in object storage instead of
           a database column.

      Scalar columns cannot be added to the allowlist: the allowlist only records
      columns that predate this guard.

      Array columns (e.g. text[]) are the one exception. PostgreSQL CHECK constraints
      cannot cap the size of individual array elements — a `cardinality(column) <= N`
      check only limits how many elements there are, not how large each one is — so an
      array column cannot be fully bounded. Add the `cardinality` limit to cap the
      count, then add the column to the allowlist, because its per-element size
      stays unbounded.
    MSG
  end

  it 'does not allow stale entries in the allowlist' do
    stale = allowlisted_columns - unbounded_columns

    expect(stale).to be_empty, <<~MSG
      The following columns are listed in #{allowlist_relative_path} but are no longer
      unbounded (they gained a size limit, or were dropped or renamed). Remove them by
      regenerating the allowlist:
        bundle exec rake gitlab:db:open_ended_columns:generate_allowlist

      #{stale.map { |c| "  - #{c}" }.join("\n")}
    MSG
  end

  describe 'the description_versions reference case' do
    it 'is captured as an unbounded column' do
      expect(unbounded_columns).to include('description_versions.description')
    end
  end
end
