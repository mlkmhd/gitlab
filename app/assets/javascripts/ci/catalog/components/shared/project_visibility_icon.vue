<script>
import { GlIcon, GlTooltipDirective } from '@gitlab/ui';

export default {
  name: 'ProjectVisibilityIcon',
  components: {
    GlIcon,
  },
  directives: {
    GlTooltip: GlTooltipDirective,
  },
};
</script>
<template>
  <gl-icon
    v-gl-tooltip
    name="lock"
    :title="
      s__('CiCatalog|Private - This component project can only be viewed by project members.')
    "
    variant="subtle"
  />
</template>
