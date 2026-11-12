<script>
import { GlButton, GlIcon, GlSkeletonLoader } from '@gitlab/ui';

export default {
  name: 'FeatureLibraryExplorePageButton',
  components: { GlButton, GlIcon, GlSkeletonLoader },
  props: {
    title: {
      type: String,
      required: false,
      default: '',
    },
    subtitle: {
      type: String,
      required: false,
      default: '',
    },
    loading: {
      type: Boolean,
      required: false,
      default: false,
    },
  },
  emits: ['select'],
};
</script>

<template>
  <div
    v-if="loading"
    class="gl-flex gl-w-full gl-items-center gl-rounded-action gl-border-1 gl-border-solid gl-border-default gl-bg-section gl-p-4"
    data-testid="feature-library-explore-page-button-loading"
  >
    <div class="gl-w-30 gl-max-w-full">
      <gl-skeleton-loader :width="240" :height="38">
        <rect y="12" width="16" height="16" rx="4" />
        <rect x="28" y="2" width="160" height="16" rx="4" />
        <rect x="28" y="24" width="200" height="12" rx="4" />
      </gl-skeleton-loader>
    </div>
  </div>

  <gl-button
    v-else
    class="gl-mt-0 gl-overflow-hidden !gl-p-0"
    button-text-classes="gl-w-full"
    data-testid="feature-library-explore-page-button"
    @click="$emit('select')"
  >
    <span
      class="gl-flex gl-items-center gl-gap-4 gl-bg-section gl-p-4 gl-text-left hover:gl-bg-subtle"
    >
      <gl-icon name="license" class="!gl-mr-0 gl-shrink-0 gl-text-subtle" />
      <span class="gl-flex gl-min-w-0 gl-grow gl-flex-col gl-gap-2">
        <span
          class="gl-font-semibold gl-text-strong"
          data-testid="feature-library-explore-page-button-title"
        >
          {{ title }}
        </span>
        <span
          class="gl-text-sm gl-text-subtle"
          data-testid="feature-library-explore-page-button-subtitle"
        >
          {{ subtitle }}
        </span>
      </span>
      <gl-icon name="chevron-lg-right" class="gl-shrink-0 gl-text-subtle" />
    </span>
  </gl-button>
</template>
