<script>
import SettingsSection from '~/vue_shared/components/settings/settings_section.vue';

export default {
  name: 'FormSection',
  components: {
    SettingsSection,
  },
  props: {
    title: {
      type: String,
      required: false,
      default: null,
    },
    isDisplay: {
      type: Boolean,
      required: false,
      default: false,
    },
  },
};
</script>

<template>
  <section v-if="isDisplay">
    <h3 v-if="title" class="gl-heading-4">{{ title }}</h3>

    <dl class="gl-mb-0 gl-flex gl-flex-col gl-gap-5">
      <slot></slot>
    </dl>
  </section>
  <settings-section v-else :heading="title">
    <div class="gl-flex gl-flex-col gl-gap-5">
      <slot></slot>
    </div>
  </settings-section>
</template>
