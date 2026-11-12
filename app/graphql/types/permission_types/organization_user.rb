# frozen_string_literal: true

module Types
  module PermissionTypes
    class OrganizationUser < BasePermissionType
      graphql_name 'OrganizationUserPermissions'

      # Only reachable through OrganizationUser.userPermissions, and
      # OrganizationUser authorizes the token with read_organization_user first.
      authorize_granular_token skip_reason: :parent_authorizes

      abilities :delete_organization_user, :admin_organization

      def admin_organization
        Ability.allowed?(context[:current_user], :update_organization, object)
      end
    end
  end
end
