<script>
import { GlBadge, GlCard, GlFormGroup, GlFormRadio, GlFormRadioGroup, GlIcon } from '@gitlab/ui';
import ScannersCard from './scanners_card.vue';

export default {
  name: 'EnableScannersSelectMode',
  components: {
    GlBadge,
    GlCard,
    GlFormGroup,
    GlFormRadio,
    GlFormRadioGroup,
    GlIcon,
    ScannersCard,
  },
  inject: ['wizard'],
  props: {
    profilesCard: {
      type: Object,
      required: false,
      default: () => ScannersCard,
    },
  },
  computed: {
    attachMode: {
      get() {
        return this.wizard.attachMode;
      },
      set(value) {
        this.wizard.attachMode = value;
      },
    },
  },
};
</script>
<template>
  <div>
    <component :is="profilesCard" editable />
    <gl-card class="gl-my-5">
      <template #header>
        <span class="gl-flex gl-items-center gl-gap-2">
          <gl-icon name="filter" />
          <strong>{{ s__('SecurityConfiguration|Mode') }}</strong>
        </span>
      </template>
      <gl-form-group
        :label="s__('SecurityConfiguration|Which projects get the scan profiles?')"
        label-sr-only
        class="gl-m-3"
      >
        <gl-form-radio-group v-model="attachMode" class="gl-flex gl-flex-col gl-gap-5">
          <gl-form-radio
            v-for="option in wizard.attachModeOptions"
            :key="option.value"
            :value="option.value"
          >
            <strong>{{ option.label }}</strong>
            <gl-badge v-if="option.recommended" variant="info">{{ __('Recommended') }}</gl-badge>
            <template #help>{{ option.help }}</template>
          </gl-form-radio>
        </gl-form-radio-group>
      </gl-form-group>
    </gl-card>
  </div>
</template>
