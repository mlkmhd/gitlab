<script>
import { GlButton, GlIcon } from '@gitlab/ui';

export default {
  name: 'AppLink',
  components: {
    GlButton,
    GlIcon,
  },
  props: {
    app: {
      type: Object,
      required: true,
    },
  },
};
</script>

<template>
  <gl-button
    :href="app.link"
    :icon="app.icon"
    target="_blank"
    class="gl-bg-status-brand gl-text-status-brand"
  >
    {{ app.title }}
    <gl-icon name="external-link" :aria-label="__('(external link)')" class="gl-ml-2" />
  </gl-button>
</template>
