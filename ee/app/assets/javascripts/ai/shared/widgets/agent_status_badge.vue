<script>
import { GlBadge } from '@gitlab/ui';
import {
  formatAgentStatusDescription,
  getAgentStatusIconVariant,
} from 'ee/ai/duo_agents_platform/utils';

export default {
  name: 'AgentStatusBadge',
  components: {
    GlBadge,
  },
  props: {
    status: {
      required: true,
      type: String,
    },
    humanStatus: {
      required: true,
      type: String,
    },
  },
  computed: {
    badge() {
      return getAgentStatusIconVariant(this.status);
    },
    variant() {
      return this.badge.variant === 'subtle' ? 'neutral' : this.badge.variant;
    },
    statusDescription() {
      return formatAgentStatusDescription(this.status);
    },
  },
};
</script>

<template>
  <gl-badge :icon="badge.icon" icon-size="sm" :variant="variant">
    <span aria-hidden="true" data-testid="status-badge-text">{{ humanStatus }}</span>
    <span class="gl-sr-only" data-testid="status-badge-description">{{ statusDescription }}</span>
  </gl-badge>
</template>
