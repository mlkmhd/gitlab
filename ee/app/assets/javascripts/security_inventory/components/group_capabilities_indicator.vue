<script>
import { GlIcon, GlPopover } from '@gitlab/ui';
import { n__, s__, sprintf } from '~/locale';
import {
  ATR_STATUS_CONFIG,
  ATR_STATUS_ENABLED,
  ATR_STATUS_NEEDS_ATTENTION,
  ATR_STATUS_NOT_ENABLED,
} from '../constants';
import SegmentedBar from './segmented_bar.vue';

export default {
  name: 'GroupCapabilitiesIndicator',
  components: { GlIcon, GlPopover, SegmentedBar },
  props: {
    item: {
      type: Object,
      required: true,
    },
  },
  computed: {
    barId() {
      return `capabilities-${this.item.path}-bar`;
    },
    labelId() {
      return `capabilities-${this.item.path}-label`;
    },
    // Roll-up of the group's projects, the three counts add up to the project total.
    counts() {
      const { enabledCount = 0, flowMissingCount = 0 } =
        this.item.triageAndRemediationCoverageCounters ?? {};
      // Groups without scan data have no analyzer statuses, so fall back to their direct projects.
      const totalProjectsCount =
        this.item.analyzerStatuses?.[0]?.totalProjectsCount ?? this.item.projectsCount ?? 0;

      return {
        [ATR_STATUS_ENABLED]: enabledCount - flowMissingCount,
        [ATR_STATUS_NEEDS_ATTENTION]: flowMissingCount,
        [ATR_STATUS_NOT_ENABLED]: Math.max(totalProjectsCount - enabledCount, 0),
      };
    },
    rows() {
      return Object.entries(this.counts).map(([key, count]) => ({
        key,
        count,
        ...ATR_STATUS_CONFIG[key],
      }));
    },
    segments() {
      return this.rows.map(({ color, count }) => ({ color, count }));
    },
  },
  methods: {
    projectsText(count) {
      return sprintf(n__('%{count} project', '%{count} projects', count), { count });
    },
  },
  i18n: {
    label: s__('SecurityInventory|Automated Triage'),
    popoverTitle: s__('SecurityInventory|Automated Triage and Remediation'),
  },
};
</script>

<template>
  <div class="gl-w-full">
    <segmented-bar
      :id="barId"
      :aria-labelledby="labelId"
      :segments="segments"
      class="gl-mb-1"
      tabindex="0"
      data-testid="capabilities-bar"
    />
    <span :id="labelId" class="gl-text-sm gl-text-status-neutral" data-testid="capabilities-label">
      {{ $options.i18n.label }}
    </span>
    <gl-popover
      :target="barId"
      :title="$options.i18n.popoverTitle"
      triggers="hover focus"
      show-close-button
      data-testid="capabilities-popover"
    >
      <ul class="gl-m-0 gl-flex gl-list-none gl-flex-col gl-gap-2 gl-p-0">
        <li
          v-for="row in rows"
          :key="row.key"
          class="gl-flex gl-items-center"
          :data-testid="`capabilities-row-${row.key}`"
        >
          <span class="gl-w-20">{{ row.text }}</span>
          <gl-icon :name="row.name" :variant="row.variant" :size="12" class="gl-mr-2" />
          <span>{{ projectsText(row.count) }}</span>
        </li>
      </ul>
    </gl-popover>
  </div>
</template>
