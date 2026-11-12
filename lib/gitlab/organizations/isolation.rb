# frozen_string_literal: true

module Gitlab
  module Organizations
    class Isolation
      # rubocop:disable Gitlab/AvoidCurrentOrganization -- We check if Current.organization is assigned so it is safe
      def self.enabled?
        return false unless begin
          Feature.enabled?(:data_isolation, Feature.current_request)
        rescue Exception # rubocop:disable Lint/RescueException -- GitLab has Errors that have Exception as parent class
          false
        end

        return false unless ::Current.organization_assigned

        # Disable organization scoping because checking isolation state can raise a ThreadError
        return false unless Gitlab::Database::DataIsolation::ScopeHelper.without_data_isolation do
          ::Current.organization&.isolated?
        end

        true
      end

      def self.organization_isolated?(organization_id)
        return false unless organization_id

        tracker = Gitlab::Organizations::FallbackOrganizationTracker
        current_organization = tracker.without_tracking { ::Current.organization if ::Current.organization_assigned }

        if current_organization&.id == organization_id
          return tracker.without_tracking do
            Gitlab::Database::DataIsolation::ScopeHelper.without_data_isolation { current_organization.isolated? }
          end
        end

        Gitlab::SafeRequestStore.fetch([:organization_isolated, organization_id]) do
          Gitlab::Database::DataIsolation::ScopeHelper.without_data_isolation do
            ::Organizations::OrganizationIsolation.isolated_organization?(organization_id)
          end
        end
      end
      # rubocop:enable Gitlab/AvoidCurrentOrganization
    end
  end
end
