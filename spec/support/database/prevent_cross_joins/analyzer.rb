# frozen_string_literal: true

module Database
  module PreventCrossJoins
    # Prevents queries that join tables from different databases.
    # Specs only: registered from spec/support/database/prevent_cross_joins.rb.
    class Analyzer < ::Gitlab::Database::QueryAnalyzers::Base
      # rubocop:disable Gitlab/DocumentationLinks/HardcodedUrl -- development docs are not served by help pages
      DOCS_URL = 'https://docs.gitlab.com/ee/development/database/multiple_databases.html' \
        '#removing-joins-between-main-and-non-main-tables'
      # rubocop:enable Gitlab/DocumentationLinks/HardcodedUrl

      class << self
        # @return [Boolean]
        def enabled?
          true
        end

        # The default key, `analyzer`, is too generic for thread-local state.
        def analyzer_key
          :prevent_cross_joins
        end

        # @param parsed [Gitlab::Database::QueryAnalyzer::Parsed]
        # @return [void]
        # @raise [CrossJoinAcrossUnsupportedTablesError] when the query joins tables from different databases
        def analyze(parsed)
          sql = parsed.raw
          return if allowed?(sql)

          tables = tables_in(parsed)
          return if ::Gitlab::Database::GitlabSchema.cross_joins_allowed?(tables)

          raise_cross_join_error(tables, sql)
        end

        private

        def tables_in(parsed)
          # PgQuery might fail in some cases due to limited nesting:
          # https://github.com/pganalyze/pg_query/issues/209
          pg = parsed.pg

          pg ? pg.tables : []
        end

        def allowed?(sql)
          return true if Thread.current[ALLOW_THREAD_KEY] || sql.include?(ALLOW_ANNOTATE_KEY)

          # Allow spec/support/database_cleaner.rb queries to disable/enable triggers for many tables
          # See https://gitlab.com/gitlab-org/gitlab/-/issues/339396
          sql.include?("DISABLE TRIGGER") || sql.include?("ENABLE TRIGGER")
        end

        def raise_cross_join_error(tables, sql)
          schemas = ::Gitlab::Database::GitlabSchema.table_schemas!(tables)

          raise CrossJoinAcrossUnsupportedTablesError,
            "Unsupported cross-join across '#{tables.join(', ')}' querying '#{schemas.to_a.join(', ')}' " \
              "discovered when executing query '#{sql}'. Please refer to #{DOCS_URL} " \
              "for details on how to resolve this exception."
        end
      end
    end
  end
end
