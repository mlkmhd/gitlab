<script>
/**
 * Default skeleton rendered by BaseLayout (and IndexLayout) while `loading` is true.
 * Mimics a generic list of items, which is the most common content of index pages.
 */
export default {
  name: 'BaseLayoutSkeleton',
  props: {
    rows: {
      type: Number,
      required: false,
      default: 5,
    },
  },
};
</script>

<template>
  <div aria-hidden="true" data-testid="base-layout-skeleton-content">
    <div
      v-for="i in rows"
      :key="i"
      class="gl-border-b gl-flex gl-items-center gl-justify-between gl-gap-5 gl-py-4"
    >
      <div class="gl-flex gl-grow gl-flex-col gl-gap-3">
        <div class="gl-animate-skeleton-loader gl-h-4 gl-w-2/5 gl-rounded-base"></div>
        <div class="gl-animate-skeleton-loader gl-h-3 gl-w-3/4 gl-rounded-base"></div>
      </div>
      <div class="gl-animate-skeleton-loader gl-h-4 gl-w-11 gl-shrink-0 gl-rounded-base"></div>
    </div>
  </div>
</template>
