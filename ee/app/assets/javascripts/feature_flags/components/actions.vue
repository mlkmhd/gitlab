<script>
import { GlDisclosureDropdown, GlTooltipDirective as GlTooltip } from '@gitlab/ui';
import { __, s__ } from '~/locale';

export default {
  name: 'FeatureFlagsActions',
  components: {
    GlDisclosureDropdown,
  },
  directives: { GlTooltip },
  inject: { searchPath: { default: '' } },
  i18n: {
    moreActions: __('More actions'),
  },
  computed: {
    items() {
      return [
        {
          text: s__('FeatureFlags|Search code references'),
          href: this.searchPath,
        },
      ];
    },
  },
};
</script>
<template>
  <gl-disclosure-dropdown
    v-if="searchPath"
    v-gl-tooltip
    icon="ellipsis_v"
    text-sr-only
    :items="items"
    :title="$options.i18n.moreActions"
    :toggle-text="$options.i18n.moreActions"
    category="tertiary"
    no-caret
    placement="bottom-end"
  />
</template>
