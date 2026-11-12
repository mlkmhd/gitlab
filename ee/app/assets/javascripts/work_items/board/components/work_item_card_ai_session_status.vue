<script>
import { GlIcon, GlTooltipDirective } from '@gitlab/ui';
import { getAgentStatusIconVariant } from 'ee/ai/duo_agents_platform/utils';

export default {
  name: 'WorkItemCardAiSessionStatus',
  components: {
    GlIcon,
  },
  directives: {
    GlTooltip: GlTooltipDirective,
  },
  props: {
    session: {
      type: Object,
      required: true,
    },
  },
  computed: {
    statusIcon() {
      return getAgentStatusIconVariant(this.session.status);
    },
  },
};
</script>

<template>
  <span
    v-gl-tooltip
    :title="session.humanStatus"
    class="gl-inline-flex gl-items-center"
    data-testid="work-item-ai-session-status"
  >
    <gl-icon
      :name="statusIcon.icon"
      :variant="statusIcon.variant"
      :size="16"
      :aria-label="session.humanStatus"
    />
  </span>
</template>
