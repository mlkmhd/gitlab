<script>
import { GlBadge, GlIcon, GlSprintf } from '@gitlab/ui';
import { n__, s__, sprintf } from '~/locale';
import { MODE_AUTOMATED, STAGE_ICONS, STAGE_LABELS } from '../constants';

export default {
  name: 'StageCard',
  components: {
    GlBadge,
    GlIcon,
    GlSprintf,
  },
  props: {
    stage: {
      type: Object,
      required: true,
    },
    position: {
      type: Number,
      required: true,
    },
    flowName: {
      type: String,
      required: false,
      default: '',
    },
    errorCount: {
      type: Number,
      required: false,
      default: 0,
    },
    selected: {
      type: Boolean,
      required: false,
      default: false,
    },
    warning: {
      type: String,
      required: false,
      default: '',
    },
  },
  emits: ['select'],
  computed: {
    label() {
      return STAGE_LABELS[this.stage.name];
    },
    icon() {
      return STAGE_ICONS[this.stage.name];
    },
    positionText() {
      return sprintf(s__('DapSoftwareFactory|Stage %{position}'), { position: this.position });
    },
    startText() {
      return this.stage.start === MODE_AUTOMATED
        ? s__('DapSoftwareFactory|Starts automatically')
        : s__('DapSoftwareFactory|Starts manually');
    },
    exitText() {
      return this.stage.exit === MODE_AUTOMATED
        ? s__('DapSoftwareFactory|Exits automatically')
        : s__('DapSoftwareFactory|Exits manually');
    },
    errorText() {
      return sprintf(
        n__(
          'DapSoftwareFactory|%{count} error',
          'DapSoftwareFactory|%{count} errors',
          this.errorCount,
        ),
        { count: this.errorCount },
      );
    },
    hasErrors() {
      return this.errorCount > 0;
    },
    showWarning() {
      return Boolean(this.warning) && !this.stage.skipped;
    },
    showMarkReady() {
      return !this.stage.skipped && this.stage.markMergeRequestsReady;
    },
    cardClasses() {
      return {
        'gl-border-dashed gl-bg-subtle gl-text-subtle': this.stage.skipped,
        'gl-bg-default gl-shadow-sm': !this.stage.skipped,
        // Selection is an outline rather than a border colour, so that it
        // stays visible on a card whose border is already showing its errors.
        'gl-outline gl-outline-2 gl-outline-offset-2 gl-outline-focus': this.selected,
        'gl-border-feedback-danger': this.hasErrors,
        'gl-border-default': !this.hasErrors,
      };
    },
  },
};
</script>

<template>
  <button
    type="button"
    class="gl-border gl-flex gl-w-30 gl-flex-col gl-gap-3 gl-rounded-lg gl-p-4 gl-text-left"
    :class="cardClasses"
    :aria-pressed="String(selected)"
    data-testid="stage-card"
    @click="$emit('select', stage.name)"
  >
    <span class="gl-flex gl-w-full gl-items-center gl-justify-between gl-gap-3">
      <span class="gl-flex gl-min-w-0 gl-items-center gl-gap-3">
        <span
          class="gl-flex gl-h-6 gl-w-6 gl-shrink-0 gl-items-center gl-justify-center gl-rounded-base gl-bg-strong gl-text-subtle"
        >
          <gl-icon :name="icon" />
        </span>
        <span class="gl-font-bold" :class="{ 'gl-text-strong': !stage.skipped }">{{ label }}</span>
      </span>
      <span class="gl-text-sm gl-text-subtle">{{ positionText }}</span>
    </span>

    <span v-if="stage.skipped" class="gl-flex gl-flex-col gl-items-start gl-gap-2 gl-text-sm">
      <gl-badge variant="neutral" icon="status_skipped_borderless" data-testid="stage-card-skipped">
        {{ s__('DapSoftwareFactory|Not enabled') }}
      </gl-badge>
      <span>{{ s__('DapSoftwareFactory|Enable this stage to configure it.') }}</span>
    </span>

    <span v-else class="gl-flex gl-flex-col gl-gap-2 gl-break-words gl-text-sm gl-text-subtle">
      <span data-testid="stage-card-status">
        <gl-sprintf v-if="stage.status" :message="s__('DapSoftwareFactory|Status: %{status}')">
          <template #status>
            <span class="gl-font-semibold gl-text-default">{{ stage.status }}</span>
          </template>
        </gl-sprintf>
        <template v-else>{{ s__('DapSoftwareFactory|No status selected') }}</template>
      </span>
      <span data-testid="stage-card-mode">
        {{ startText }} <span aria-hidden="true">&middot;</span> {{ exitText }}
      </span>
      <span v-if="flowName" data-testid="stage-card-flow">
        <gl-sprintf :message="s__('DapSoftwareFactory|Flow: %{flow}')">
          <template #flow>
            <span class="gl-font-semibold gl-text-link">{{ flowName }}</span>
          </template>
        </gl-sprintf>
      </span>
    </span>

    <span v-if="showWarning" class="gl-text-sm gl-text-warning" data-testid="stage-card-warning">
      <gl-icon name="warning" :size="12" class="gl-mr-1" />{{ warning }}
    </span>

    <span v-if="hasErrors || showMarkReady" class="gl-flex gl-flex-wrap gl-gap-2">
      <gl-badge v-if="hasErrors" variant="danger" icon="error" data-testid="stage-card-errors">
        {{ errorText }}
      </gl-badge>
      <gl-badge
        v-if="showMarkReady"
        variant="success"
        icon="merge-request"
        data-testid="stage-card-mark-ready"
      >
        {{ s__('DapSoftwareFactory|Marks MRs ready') }}
      </gl-badge>
    </span>
  </button>
</template>
