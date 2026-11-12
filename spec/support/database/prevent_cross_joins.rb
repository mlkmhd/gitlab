# frozen_string_literal: true

require_relative 'prevent_cross_joins/analyzer'

# This module tries to discover and prevent cross-joins across tables
# This will forbid usage of tables of different gitlab_schemas
# on a same query unless explicitly allowed by. This will change execution
# from a given point to allow cross-joins. The state will be cleared
# on a next test run.
#
# This method should be used to mark METHOD introducing cross-join
# not a test using the cross-join.
#
# class User
#   def ci_available_runners
#     ::Gitlab::Database.allow_cross_joins_across_databases(url: link-to-issue-url)
#
#     ...
#   end
# end

module Database
  module PreventCrossJoins
    CrossJoinAcrossUnsupportedTablesError = Class.new(StandardError)

    ALLOW_THREAD_KEY = :allow_cross_joins_across_databases
    ALLOW_ANNOTATE_KEY = ALLOW_THREAD_KEY.to_s.freeze

    # Suppresses the analyzer in all threads, because Puma threads in feature specs
    # do not share the example thread's state.
    def self.with_allowlist_for(file_path)
      previous = Analyzer.suppress_in_rspec
      Analyzer.suppress_in_rspec = ALLOW_LIST.include?(file_path)

      yield
    ensure
      Analyzer.suppress_in_rspec = previous
    end

    module SpecHelpers
      def with_cross_joins_prevented(&block)
        previous = Analyzer.suppress_in_rspec
        Analyzer.suppress_in_rspec = false

        prevent_cross_joins_in_current_thread(&block)
      ensure
        Analyzer.suppress_in_rspec = previous
      end

      def allow_cross_joins_across_databases(url:, &block)
        ::Gitlab::Database.allow_cross_joins_across_databases(url: url, &block)
      end

      private

      def prevent_cross_joins_in_current_thread
        thread = Thread.current
        previous = thread[ALLOW_THREAD_KEY]
        thread[ALLOW_THREAD_KEY] = false

        ::Gitlab::Database::QueryAnalyzer.instance.within([Analyzer]) { yield }
      ensure
        thread[ALLOW_THREAD_KEY] = previous
      end
    end

    module GitlabDatabaseMixin
      def allow_cross_joins_across_databases(url:)
        old_value = Thread.current[ALLOW_THREAD_KEY]
        Thread.current[ALLOW_THREAD_KEY] = true

        yield
      ensure
        Thread.current[ALLOW_THREAD_KEY] = old_value
      end
    end

    module ActiveRecordRelationMixin
      def allow_cross_joins_across_databases(url:)
        super.annotate(ALLOW_ANNOTATE_KEY)
      end
    end
  end
end

Gitlab::Database.singleton_class.prepend(
  Database::PreventCrossJoins::GitlabDatabaseMixin)

ActiveRecord::Relation.prepend(
  Database::PreventCrossJoins::ActiveRecordRelationMixin)

Gitlab::Database::QueryAnalyzer.instance.all_analyzers.append(Database::PreventCrossJoins::Analyzer)

ALLOW_LIST = Set.new(YAML.load_file(File.join(__dir__, 'cross-join-allowlist.yml'))).freeze

RSpec.configure do |config|
  config.include(::Database::PreventCrossJoins::SpecHelpers)

  config.around do |example|
    Database::PreventCrossJoins.with_allowlist_for(example.file_path_rerun_argument) { example.run }
  end
end
