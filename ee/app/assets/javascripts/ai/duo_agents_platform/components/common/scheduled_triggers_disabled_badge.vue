<script>
import { GlBadge, GlTooltipDirective } from '@gitlab/ui';
import { s__ } from '~/locale';
import {
  isScheduledTriggersBetaAvailable,
  isScheduledTriggersDisabled,
} from 'ee/ai/duo_agents_platform/utils';

export default {
  name: 'ScheduledTriggersDisabledBadge',
  components: {
    GlBadge,
  },
  directives: {
    GlTooltip: GlTooltipDirective,
  },
  inject: {
    duoSettings: {
      default: () => ({}),
    },
  },
  props: {
    scheduled: {
      type: Boolean,
      required: true,
    },
    active: {
      type: Boolean,
      required: true,
    },
  },
  computed: {
    betaUnavailable() {
      return !isScheduledTriggersBetaAvailable(this.duoSettings);
    },
    show() {
      return (
        this.scheduled &&
        this.active &&
        (this.betaUnavailable || isScheduledTriggersDisabled(this.duoSettings))
      );
    },
    tooltip() {
      if (this.betaUnavailable) {
        return s__(
          'DuoAgentsPlatform|Scheduled automations need experiment and beta features. This schedule is kept but does not run.',
        );
      }

      return s__(
        'DuoAgentsPlatform|Scheduled automations are turned off in GitLab Duo settings. This schedule is kept but does not run.',
      );
    },
  },
};
</script>

<template>
  <gl-badge
    v-if="show"
    v-gl-tooltip="tooltip"
    variant="neutral"
    icon="clock"
    tabindex="0"
    data-testid="scheduled-triggers-disabled-badge"
    >{{ s__('DuoAgentsPlatform|Not running') }}</gl-badge
  >
</template>
