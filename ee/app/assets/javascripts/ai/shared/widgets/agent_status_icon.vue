<script>
import { GlIcon } from '@gitlab/ui';
import { getAgentStatusIconVariant } from 'ee/ai/duo_agents_platform/utils';

export default {
  name: 'AgentStatusIcon',
  components: {
    GlIcon,
  },
  props: {
    status: {
      required: true,
      type: String,
    },
    label: {
      required: false,
      type: String,
      default: null,
    },
  },
  computed: {
    itemStatus() {
      return getAgentStatusIconVariant(this.status);
    },
  },
};
</script>

<template>
  <gl-icon :name="itemStatus.icon" :aria-label="label" :size="12" :variant="itemStatus.variant" />
</template>
