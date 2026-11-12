<script>
import { GlExperimentBadge, GlLink } from '@gitlab/ui';

export default {
  name: 'DashboardsListNameCell',
  components: {
    GlExperimentBadge,
    GlLink,
  },
  props: {
    name: {
      type: String,
      required: true,
    },
    description: {
      type: String,
      required: false,
      default: '',
    },
    dashboardUrl: {
      type: String,
      required: true,
    },
    status: {
      type: String,
      required: false,
      default: null,
    },
    system: {
      type: Boolean,
      required: false,
      default: false,
    },
    // Opt-in because the cell also renders inside GlTable rows, which are
    // not positioned, so a stretched link there would cover the whole table.
    stretched: {
      type: Boolean,
      required: false,
      default: false,
    },
  },
  computed: {
    showStatusBadge() {
      return Boolean(this.system && this.status);
    },
  },
};
</script>
<template>
  <div class="gl-min-w-0">
    <div class="gl-flex gl-items-center">
      <gl-link
        data-testid="dashboard-redirect-link"
        :href="dashboardUrl"
        class="gl-min-w-0 gl-font-bold !gl-text-strong gl-break-anywhere"
        :class="{ 'gl-stretched-link': stretched }"
        >{{ name }}</gl-link
      >
      <gl-experiment-badge
        v-if="showStatusBadge"
        data-testid="dashboard-status-badge"
        :type="status"
      />
    </div>
    <!-- The native title recovers the clamped text; a stretched link can cover
         the paragraph, so it cannot be selected or hovered as a GlTooltip target. -->
    <p
      v-if="description"
      :title="description"
      class="gl-m-0 gl-line-clamp-2 gl-text-sm gl-text-subtle gl-break-anywhere"
      data-testid="dashboard-description"
    >
      {{ description }}
    </p>
  </div>
</template>
