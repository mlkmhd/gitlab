# frozen_string_literal: true

module Gitlab
  module Duo
    module CodeReview
      module Availability
        class Project < Base
          alias_method :project, :container

          def available?
            check_duo_features(foundational_flows: false) do
              next true if project.duo_code_review_dap_available?

              # Classic Duo Enterprise flow fallback
              project.namespace.has_active_add_on_purchase?([:duo_enterprise])
            end
          end

          def depth_settings_available?
            return false if ::Feature.disabled?(:duo_code_review_deep_flow, project.root_ancestor)

            check_duo_features(beta: true)
          end

          def decisions_settings_available?
            return false if ::Feature.disabled?(:duo_code_review_decisions, project)

            check_duo_features(beta: true) { available? }
          end

          private

          def duo_beta_features_enabled?
            project.root_ancestor.duo_beta_flows_enabled?
          end
        end
      end
    end
  end
end
