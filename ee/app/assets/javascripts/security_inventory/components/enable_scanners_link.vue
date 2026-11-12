<script>
import { GlLink } from '@gitlab/ui';
import { s__ } from '~/locale';
import { ENABLE_SCANNERS_ROUTE, SECURITY_CONFIGURATION_PATH } from '../constants';

export default {
  name: 'EnableScannersLink',
  components: {
    GlLink,
  },
  props: {
    webPath: {
      type: String,
      required: false,
      default: null,
    },
  },
  computed: {
    configurationPath() {
      if (!this.webPath) return null;
      return `${this.webPath}${SECURITY_CONFIGURATION_PATH}`;
    },
    enableScannersPath() {
      if (!this.configurationPath) return null;
      return `${this.configurationPath}${ENABLE_SCANNERS_ROUTE}`;
    },
  },
  i18n: {
    enableScanners: s__('SecurityInventory|Enable scanners'),
  },
};
</script>

<template>
  <gl-link v-if="enableScannersPath" :href="enableScannersPath" data-testid="enable-scanners-link">
    {{ $options.i18n.enableScanners }}
  </gl-link>
</template>
