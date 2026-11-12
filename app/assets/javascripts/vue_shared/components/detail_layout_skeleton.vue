<script>
/**
 * Skeleton rendered by DetailLayout while `loading` is true.
 * Based on the work item loading state (see work_items/components/work_item_loading.vue).
 * It reuses the DetailLayout grid classes so each placeholder region lands exactly where
 * the real slot content will render, and only renders regions for slots the page uses.
 */
export default {
  name: 'DetailLayoutSkeleton',
  loader: {
    descriptionLines: 4,
    sidebarAttributes: 6,
    widgets: 2,
    activityNotes: 5,
  },
  props: {
    sidebar: {
      type: Boolean,
      required: false,
      default: false,
    },
    widgets: {
      type: Boolean,
      required: false,
      default: false,
    },
    activity: {
      type: Boolean,
      required: false,
      default: false,
    },
  },
};
</script>

<template>
  <div
    class="gl-detail-layout-container"
    :class="{ 'gl-detail-layout-container-has-sidebar': sidebar }"
    aria-hidden="true"
    data-testid="detail-layout-skeleton"
  >
    <div
      class="gl-detail-layout-content gl-flex gl-flex-col gl-gap-3"
      data-testid="detail-layout-skeleton-content"
    >
      <slot>
        <div
          v-for="i in $options.loader.descriptionLines"
          :key="i"
          class="gl-animate-skeleton-loader gl-h-4 gl-max-w-full gl-rounded-base"
        ></div>
        <div class="gl-animate-skeleton-loader gl-h-4 gl-w-3/4 gl-rounded-base"></div>
      </slot>
    </div>

    <div
      v-if="sidebar"
      class="gl-detail-layout-sidebar gl-flex !gl-h-auto gl-flex-col gl-gap-6"
      data-testid="detail-layout-skeleton-sidebar"
    >
      <div
        v-for="i in $options.loader.sidebarAttributes"
        :key="i"
        class="gl-flex gl-flex-col gl-gap-3"
      >
        <div class="gl-animate-skeleton-loader gl-h-3 gl-w-1/5 gl-rounded-base"></div>
        <div class="gl-animate-skeleton-loader gl-h-4 gl-max-w-full gl-rounded-base"></div>
      </div>
    </div>

    <div
      v-if="widgets"
      class="gl-detail-layout-widgets gl-flex gl-flex-col gl-gap-5"
      data-testid="detail-layout-skeleton-widgets"
    >
      <div
        v-for="i in $options.loader.widgets"
        :key="i"
        class="gl-animate-skeleton-loader gl-h-11 gl-max-w-full gl-rounded-base"
      ></div>
    </div>

    <div
      v-if="activity"
      class="gl-detail-layout-activity gl-flex gl-flex-col gl-gap-5"
      data-testid="detail-layout-skeleton-activity"
    >
      <div class="gl-animate-skeleton-loader gl-h-7 gl-w-20 gl-max-w-full gl-rounded-base"></div>
      <div class="gl-flex gl-flex-col gl-gap-3">
        <div
          v-for="i in $options.loader.activityNotes"
          :key="i"
          class="gl-flex gl-items-center gl-gap-3"
        >
          <div class="gl-animate-skeleton-loader gl-h-7 gl-w-7 gl-shrink-0 gl-rounded-full"></div>
          <div
            class="gl-animate-skeleton-loader gl-h-5 gl-w-75 gl-max-w-full gl-rounded-base"
          ></div>
        </div>
      </div>
    </div>
  </div>
</template>
