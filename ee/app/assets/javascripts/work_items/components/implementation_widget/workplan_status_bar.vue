<script>
import { AGENT_STEP_PILL_VARIANTS } from './constants';
import { getVariantColor } from './utils';

const ANIMATED_VARIANT = 'duo';

export default {
  name: 'WorkplanStatusBar',
  props: {
    variant: {
      type: String,
      required: true,
      validator: (value) => Object.keys(AGENT_STEP_PILL_VARIANTS).includes(value),
    },
  },
  computed: {
    isAnimated() {
      return this.variant === ANIMATED_VARIANT;
    },
    barBgClass() {
      const color = getVariantColor(this.variant);
      // The animation sets the background size, which the `background` shorthand would reset.
      return this.isAnimated ? { backgroundImage: color } : { background: color };
    },
  },
};
</script>
<template>
  <div
    class="gl-h-full gl-min-h-5 gl-w-2 gl-flex-shrink-0 gl-self-stretch gl-rounded-full"
    :class="{ 'workplan-status-bar-animated': isAnimated }"
    :style="barBgClass"
  ></div>
</template>
