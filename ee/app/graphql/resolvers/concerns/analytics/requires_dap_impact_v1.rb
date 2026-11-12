# frozen_string_literal: true

module Analytics
  # Users and root groups are both `dap_impact_v1` actors: without the flag, a user needs every
  # source under an enabled root group. Checked after authorization so the error cannot reveal
  # the flag state of groups the user cannot read.
  module RequiresDapImpactV1
    private

    def aggregation_sources(arguments)
      sources = super
      return sources if Feature.enabled?(:dap_impact_v1, current_user)

      all_enabled = sources.all? do |source|
        namespace = source.is_a?(::Project) ? source.namespace : source

        Feature.enabled?(:dap_impact_v1, ::Group.actor_from_id(namespace.traversal_ids.first))
      end

      raise_resource_not_available_error! '`dap_impact_v1` feature flag is disabled.' unless all_enabled

      sources
    end
  end
end
