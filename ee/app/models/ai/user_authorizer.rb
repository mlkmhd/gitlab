# frozen_string_literal: true

module Ai
  # Answers Duo access questions for one user. Replaces the methods that
  # Ai::UserAuthorizable adds to User; see
  # https://gitlab.com/gitlab-org/gitlab/-/work_items/636699
  class UserAuthorizer
    # refers to add-ons listed in GitlabSubscriptions::SystemDefined::AddOn::DUO_ADD_ONS
    DUO_ADD_ONS_CACHE_KEY = 'user-%{user_id}-duo-add-ons-cache'
    GROUP_WITH_MCP_SERVER_ENABLED_CACHE_KEY = 'group_with_mcp_server_enabled'
    GROUP_WITH_MCP_SERVER_ENABLED_CACHE_PERIOD = 1.hour
    ROOT_GROUP_IDS_CACHE_KEY = 'root_group_ids'
    ROOT_GROUP_IDS_CACHE_PERIOD = 10.minutes

    # One authorizer per user per request, so memoized lookups are shared by every caller.
    def self.for(user)
      return new(user) unless user&.id

      Gitlab::SafeRequestStore.fetch([:ai_user_authorizer, user.id]) { new(user) }
    end

    def initialize(user)
      @user = user
    end

    def any_group_with_mcp_server_enabled?
      Rails.cache.fetch(
        ['users', user.id, GROUP_WITH_MCP_SERVER_ENABLED_CACHE_KEY],
        expires_in: GROUP_WITH_MCP_SERVER_ENABLED_CACHE_PERIOD
      ) do
        ::Group.by_id(gitlab_com_root_group_ids).with_mcp_server_enabled.any?
      end
    end

    def eligible_for_self_managed_gitlab_duo_pro?
      return false if user.gitlab_com_subscription?

      user.active? && !user.bot? && !user.ghost?
    end

    # rubocop: disable Database/AvoidUsingPluckWithoutLimit -- limited to a single user's groups
    def gitlab_com_root_group_ids
      return unless user.gitlab_com_subscription?

      Rails.cache.fetch(
        ['users', user.id, ROOT_GROUP_IDS_CACHE_KEY],
        expires_in: ROOT_GROUP_IDS_CACHE_PERIOD
      ) do
        banned_root_group_ids = ::Namespaces::NamespaceBan.where(user_id: user.id).pluck(:namespace_id)

        user.authorized_root_ancestor_ids - banned_root_group_ids
      end
    end
    # rubocop: enable Database/AvoidUsingPluckWithoutLimit -- limited to a single user's groups

    def default_duo_namespace
      user.user_preference.duo_default_namespace_with_fallback
    end

    def duo_available_namespace_ids
      Rails.cache.fetch(duo_addons_cache_key_formatted, expires_in: 1.hour) do
        GitlabSubscriptions::UserAddOnAssignment.by_user(user).for_active_gitlab_duo_purchase
          .pluck('subscription_add_on_purchases.namespace_id') # rubocop: disable Database/AvoidUsingPluckWithoutLimit -- limited to a single user's purchases
          .uniq
      end
    end

    private

    attr_reader :user

    def duo_addons_cache_key_formatted
      format(DUO_ADD_ONS_CACHE_KEY, user_id: user.id)
    end
  end
end
