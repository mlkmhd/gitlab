<script>
import {
  formatAgentStatus,
  formatAgentStatusDescription,
  getAgentStatusTextClass,
} from 'ee/ai/duo_agents_platform/utils';
import AgentStatusIcon from 'ee/ai/shared/widgets/agent_status_icon.vue';
import {
  AGENT_SESSION_INBOX_ACTION_STATUSES,
  AGENT_SESSION_INBOX_STATUS_LABELS,
} from './constants';
import InboxRow from './inbox_row.vue';

export default {
  name: 'AgentSessionInboxItem',
  components: { AgentStatusIcon, InboxRow },
  props: {
    item: {
      required: true,
      type: Object,
    },
  },
  computed: {
    statusDescription() {
      return formatAgentStatusDescription(this.item.status);
    },
    statusLabel() {
      return (
        AGENT_SESSION_INBOX_STATUS_LABELS[this.item.status] ??
        formatAgentStatus(this.item.humanStatus)
      );
    },
    isActionLabel() {
      return AGENT_SESSION_INBOX_ACTION_STATUSES.includes(this.item.status);
    },
    statusTextClass() {
      return getAgentStatusTextClass(this.item.status);
    },
  },
};
</script>
<template>
  <inbox-row :item="item">
    <template #icon>
      <agent-status-icon :status="item.status" :label="statusDescription" />
    </template>
    <template #status>
      <span
        class="gl-shrink-0 gl-font-semibold"
        :class="statusTextClass"
        :aria-hidden="isActionLabel ? null : 'true'"
        data-testid="item-status-label"
        >{{ statusLabel }}</span
      >
    </template>
  </inbox-row>
</template>
