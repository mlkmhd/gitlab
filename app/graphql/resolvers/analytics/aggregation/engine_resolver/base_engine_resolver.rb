# frozen_string_literal: true

module Resolvers
  module Analytics
    module Aggregation
      module EngineResolver
        class BaseEngineResolver < BaseResolver # rubocop:disable Graphql/ResolverType -- type declared in subclasses
          class << self
            attr_accessor :engine
          end

          # Ability checked against every requested group or project.
          # Set while mounting an engine.
          class_attribute :resource_ability

          # Bounds on a single request, enforced behind `aggregation_engine_request_limits`.
          MAX_DATE_RANGE_SPAN = 366.days
          MAX_DIMENSIONS = 10
          MAX_METRICS = 20

          argument :descendants_scope, ::Types::Analytics::Aggregation::ScopeInputType,
            required: false,
            description: 'Child groups and projects to aggregate data for. Not supported at project level.'

          def resolve(**arguments)
            authorize!(object) if self.class.authorization.any?

            non_metric_filters = engine_class.filters.reject(&:metric?)
            filters = ::Gitlab::Database::Aggregation::Graphql::Adapter
              .arguments_to_filters(non_metric_filters, arguments)
            request = ::Gitlab::Database::Aggregation::Request.new(filters: filters, metrics: [])

            {
              engine: engine_class.new(context: engine_context(arguments)),
              request: request,
              validate_request: method(:validate_request!)
            }
          end

          private

          def engine_class
            self.class.engine
          end

          # Mount blocks may override this to limit requests further; overrides
          # must call `super` to keep the limits below.
          def validate_request!(engine_request)
            return unless Feature.enabled?(:aggregation_engine_request_limits, request_limits_actor)

            validate_date_range!(engine_request)
            validate_parts_count!(engine_request)
          end

          # Gated by top-level namespace so one actor covers every project and
          # subgroup under it; an organization is its own actor.
          def request_limits_actor
            return object unless object.respond_to?(:root_ancestor)

            object.root_ancestor || object
          end

          # Without a date range start the aggregation reads every row under the requested scope.
          # A range with no end (`createdAt >= -30d` in GLQL) is measured up to now.
          def validate_date_range!(engine_request)
            date_filters = engine_class.filters.select { |filter| date_range_filter?(filter) }
            return if date_filters.empty?

            identifiers = date_filters.map(&:identifier)
            bounded = engine_request.filters.filter_map do |config|
              range = config[:values]
              next unless identifiers.include?(config[:identifier]) && range.is_a?(Range) && range.begin

              [config[:identifier], range.begin, range.end || Time.current]
            end

            if bounded.empty?
              arguments = identifiers.map { |identifier| "#{graphql_name_for(identifier)}From" }

              raise ::Gitlab::Graphql::Errors::ArgumentError,
                "a date range start is required: set #{arguments.join(' or ')}"
            end

            identifier, _start, _finish = bounded.detect { |_, start, finish| finish > start + MAX_DATE_RANGE_SPAN }
            return unless identifier

            raise ::Gitlab::Graphql::Errors::ArgumentError,
              "the #{graphql_name_for(identifier)} date range may not span more than " \
                "#{MAX_DATE_RANGE_SPAN.in_days.to_i} days"
          end

          def validate_parts_count!(engine_request)
            if engine_request.dimensions.size > MAX_DIMENSIONS
              raise ::Gitlab::Graphql::Errors::ArgumentError,
                "too many dimensions requested: #{engine_request.dimensions.size} of a maximum of #{MAX_DIMENSIONS}"
            end

            return unless engine_request.metrics.size > MAX_METRICS

            raise ::Gitlab::Graphql::Errors::ArgumentError,
              "too many metrics requested: #{engine_request.metrics.size} of a maximum of #{MAX_METRICS}"
          end

          def date_range_filter?(filter)
            filter.is_a?(::Gitlab::Database::Aggregation::ClickHouse::RangeFilter) &&
              %i[date datetime].include?(filter.type.to_sym)
          end

          def graphql_name_for(identifier)
            identifier.to_s.camelize(:lower)
          end

          # Sources are already authorized against `resource_ability`; they are
          # passed along so engines can run part-level authorization checks.
          def engine_context(arguments)
            sources = aggregation_sources(arguments)

            {
              scope: engine_class.prepare_base_aggregation_scope(sources),
              current_user: current_user,
              authorization_resources: sources
            }
          end

          def aggregation_sources(arguments)
            scope = arguments[:descendants_scope] || {}
            group_paths = Array(scope[:group_full_paths])
            project_paths = Array(scope[:project_full_paths])

            case object
            when ::Project
              # Project-level analytics are always scoped to the project itself.
              if group_paths.any? || project_paths.any?
                raise ::Gitlab::Graphql::Errors::ArgumentError,
                  'groupFullPaths and projectFullPaths arguments are not supported at project level'
              end

              project_paths = [object.full_path]
            when ::Group
              # At group level the arguments are optional: the group itself is
              # aggregated when no sources are requested.
              group_paths = [object.full_path] if group_paths.empty? && project_paths.empty?
            end

            if group_paths.empty? && project_paths.empty?
              raise ::Gitlab::Graphql::Errors::ArgumentError,
                'at least one of the groupFullPaths or projectFullPaths arguments is required'
            end

            authorized_sources!(group_paths, project_paths)
          end

          def authorized_sources!(group_paths, project_paths)
            paths = (group_paths + project_paths).uniq(&:downcase)

            sources_by_path = load_sources(group_paths, project_paths)

            accessible, inaccessible = paths.partition do |path|
              source = sources_by_path[path.downcase]
              source && Ability.allowed?(current_user, resource_ability, source)
            end

            # Missing, out-of-scope, and unauthorized sources are reported
            # identically, so the error does not disclose whether an inaccessible
            # source exists.
            if inaccessible.any?
              raise_resource_not_available_error!(
                format(s_("AggregationEngine|The following sources are not accessible: %{source_ids}"),
                  source_ids: inaccessible.join(', ')),
                { code: AggregationFieldResolver::BaseAggregationFieldResolver::NOT_AUTHORIZED_CODE }
              )
            end

            accessible.map { |path| sources_by_path[path.downcase] }
          end

          def load_sources(group_paths, project_paths)
            sources = load_records(::Group, group_paths, ::Preloaders::GroupPolicyPreloader) +
              load_records(::Project, project_paths, ::Preloaders::ProjectPolicyPreloader)

            sources.index_by { |record| record.full_path.downcase }
          end

          def load_records(model_class, paths, preloader_class)
            return [] if paths.empty?

            records = source_scope(model_class).where_full_path_in(paths).to_a
            preloader_class.new(records, current_user).execute

            records
          end

          def source_scope(model_class)
            case object
            when ::Group
              model_class == ::Group ? object.self_and_descendants : object.all_projects
            when ::Project
              # Only the project itself is ever loaded at project level.
              model_class.id_in(object.id)
            else
              model_class.in_organization(object)
            end
          end
        end
      end
    end
  end
end
