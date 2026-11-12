<script>
import { GlTooltipDirective, GlButton } from '@gitlab/ui';
import { s__ } from '~/locale';

/**
 * Renders the external url link in environments table.
 */
export default {
  name: 'EnvironmentExternalUrl',
  components: {
    GlButton,
  },
  directives: {
    GlTooltip: GlTooltipDirective,
  },
  props: {
    externalUrl: {
      type: String,
      required: true,
    },
  },
  i18n: {
    title: s__('Environments|Open live environment'),
  },
};
</script>
<template>
  <gl-button
    v-gl-tooltip
    :title="$options.i18n.title"
    :aria-label="$options.i18n.title"
    :href="externalUrl"
    is-unsafe-link
    class="external-url"
    target="_blank"
    icon="external-link"
    rel="noopener noreferrer nofollow"
  >
    {{ s__('Environments|Open') }}
  </gl-button>
</template>
