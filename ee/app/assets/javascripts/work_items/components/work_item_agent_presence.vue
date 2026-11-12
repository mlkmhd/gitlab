<script>
import AgentActorLine from 'ee/ai/shared/widgets/agent_actor_line.vue';
import { parseAgentPresence } from '~/ai/agents_utils';
import glFeatureFlagsMixin from '~/vue_shared/mixins/gl_feature_flags_mixin';
import workItemAgentPresenceQuery from '../graphql/work_item_agent_presence.query.graphql';

export default {
  name: 'WorkItemAgentPresence',
  components: {
    AgentActorLine,
  },
  mixins: [glFeatureFlagsMixin()],
  props: {
    fullPath: {
      type: String,
      required: true,
    },
    workItemIid: {
      type: String,
      required: false,
      default: null,
    },
  },
  data() {
    return {
      agentPresence: null,
    };
  },
  computed: {
    canViewSession() {
      return Boolean(this.agentPresence?.userPermissions?.readDuoWorkflow);
    },
  },
  apollo: {
    agentPresence: {
      query: workItemAgentPresenceQuery,
      variables() {
        return {
          fullPath: this.fullPath,
          iid: this.workItemIid,
        };
      },
      skip() {
        return !this.glFeatures.agentPresenceConsolidation || !this.workItemIid;
      },
      update(data) {
        return parseAgentPresence(data.namespace?.workItem?.agentPresence);
      },
    },
  },
};
</script>

<template>
  <span v-if="agentPresence">
    <span aria-hidden="true" class="gl-align-middle" data-testid="actor-line-separator"
      >&middot;</span
    >
    <agent-actor-line
      class="gl-align-middle"
      :agent-name="agentPresence.agentName"
      :agent-catalog-path="agentPresence.agentCatalogWebPath"
      :session-id="agentPresence.sessionId"
      :user="agentPresence.user"
      :trigger-source="agentPresence.triggerSource"
      :can-view-session="canViewSession"
      with-agent-name
    />
  </span>
</template>
