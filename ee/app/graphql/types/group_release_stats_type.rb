# frozen_string_literal: true

module Types
  class GroupReleaseStatsType < BaseObject
    graphql_name 'GroupReleaseStats'
    description 'Contains release-related statistics about a group'

    authorize :read_group_release_stats
    authorize_granular_token permissions: :read_release, boundary: :itself, boundary_type: :group

    field :releases_count,
      GraphQL::Types::Int,
      null: true,
      description: 'Total number of releases in all descendant projects of the group.'

    field :releases_percentage,
      GraphQL::Types::Int,
      null: true,
      description: "Percentage of the group's descendant projects that have at least one release."

    def releases_count
      push_namespace_context

      object.releases_count
    end

    def releases_percentage
      push_namespace_context

      object.releases_percentage
    end

    private

    # Both fields aggregate over the whole group hierarchy. Record the group so
    # the GraphQL request log shows which namespace the cost belongs to.
    def push_namespace_context
      ::Gitlab::ApplicationContext.push(namespace: object)
    end
  end
end
