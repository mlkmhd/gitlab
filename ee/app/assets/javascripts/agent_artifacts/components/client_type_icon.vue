<script>
import { GlAvatar, GlIcon } from '@gitlab/ui';

export default {
  name: 'ClientTypeIcon',
  components: {
    GlAvatar,
    GlIcon,
  },
  props: {
    clientType: {
      type: Object,
      required: true,
    },
    logo: {
      type: String,
      required: false,
      default: null,
    },
    logoClass: {
      type: String,
      required: false,
      default: null,
    },
  },
};
</script>

<template>
  <img
    v-if="logo"
    :src="logo"
    :class="logoClass"
    :alt="''"
    width="16"
    height="16"
    class="gl-shrink-0 gl-object-contain"
    data-testid="client-type-logo"
  />
  <gl-icon v-else-if="clientType.icon" :name="clientType.icon" :size="16" class="gl-shrink-0" />
  <gl-avatar v-else :entity-name="clientType.name" :size="16" class="gl-shrink-0" />
</template>
