# frozen_string_literal: true

module Mutations
  module Ai
    module Catalog
      # Rate limits the mutations that send an agent or flow configuration to the
      # Duo Workflow Service for validation. All of them share one counter per user.
      module ConfigValidationRateLimitable
        extend ActiveSupport::Concern
        include ::Mutations::Ai::Catalog::RateLimitable

        CONFIG_VALIDATION_RATE_LIMIT_KEY = :ai_catalog_config_validation

        private

        def config_validation_rate_limited?
          rate_limited?(CONFIG_VALIDATION_RATE_LIMIT_KEY, scope: { user: current_user })
        end

        def config_validation_rate_limited_message
          s_('AICatalog|You have saved agents, flows, or triggers too many times. Try again in a minute.')
        end
      end
    end
  end
end
