# frozen_string_literal: true

module Types
  module PermissionTypes
    class User < BasePermissionType
      graphql_name 'UserPermissions'

      # Only reachable through userPermissions on the user types (UserCore and
      # the types built on it), which authorize the token with read_user first.
      authorize_granular_token skip_reason: :parent_authorizes

      permission_field :create_snippet

      def create_snippet
        Ability.allowed?(context[:current_user], :create_snippet)
      end
    end
  end
end
