# frozen_string_literal: true

module Ai
  module DuoSettings
    # Foundational agents on a group's GitLab Duo settings page.
    class FoundationalAgentsPresenter
      # @param group [Group]
      # @param current_user [User]
      def initialize(group, current_user:)
        @group = group
        @current_user = current_user
      end

      # The agents the settings page lists. Like {Admin::AiConfigurationPresenter#foundational_agents_statuses}, it
      # hides the Orbit agent from users without Orbit, and the Ultimate-only agents without the license.
      #
      # @return [Array<Hash>] as {Ai::FoundationalAgentsStatusable#foundational_agents_statuses} returns them
      def listed_statuses
        statuses = group.root_ancestor.foundational_agents_statuses
        statuses = statuses.reject { |status| status[:reference] == 'orbit_agent' } unless orbit_enabled?
        return statuses if group.licensed_feature_available?(:ai_features)

        ultimate_only_references = ::Ai::FoundationalChatAgent.ultimate_only_references
        statuses.reject { |status| ultimate_only_references.include?(status[:reference]) }
      end

      # Whether the group readiness card renders. The flag rolls out per top-level group.
      #
      # @return [Boolean]
      def readiness_card_enabled?
        ::Feature.enabled?(:duo_group_agent_readiness_settings, group.root_ancestor, type: :wip)
      end

      # The listed agents the top-level group turned on, which its projects list read-only. Resolved the way
      # the agents run, so nothing is selected while the Agents switch is off, and an agent that a feature flag
      # still hides at runtime is left out.
      #
      # @return [Array<Hash>] the {#listed_statuses} entries whose agent is on
      def selected_statuses
        enabled_references = group.root_ancestor.enabled_foundational_agents.map(&:reference)
        enabled_references.delete('onboarding_guide') unless onboarding_guide_enabled?
        listed_statuses.select { |status| enabled_references.include?(status[:reference]) }
      end

      private

      attr_reader :group, :current_user

      def orbit_enabled?
        ::Analytics::KnowledgeGraph.enabled_for?(current_user)
      end

      # The same gate as Ai::FoundationalChatAgentsFinder#onboarding_guide_disabled?: on GitLab.com the
      # top-level group is the flag's actor.
      def onboarding_guide_enabled?
        ::Feature.enabled?(:onboarding_guide_agent, group.root_ancestor)
      end
    end
  end
end
