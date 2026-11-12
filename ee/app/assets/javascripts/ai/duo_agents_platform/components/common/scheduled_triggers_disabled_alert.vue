<script>
import { GlAlert, GlLink, GlSprintf } from '@gitlab/ui';
import { s__ } from '~/locale';
import {
  isScheduledTriggersBetaAvailable,
  isScheduledTriggersDisabled,
} from 'ee/ai/duo_agents_platform/utils';

export default {
  name: 'ScheduledTriggersDisabledAlert',
  components: {
    GlAlert,
    GlLink,
    GlSprintf,
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
  },
  computed: {
    betaUnavailable() {
      return !isScheduledTriggersBetaAvailable(this.duoSettings);
    },
    show() {
      return (
        this.scheduled && (this.betaUnavailable || isScheduledTriggersDisabled(this.duoSettings))
      );
    },
    title() {
      return this.betaUnavailable
        ? s__('DuoAgentsPlatform|Scheduled automations are not available')
        : s__('DuoAgentsPlatform|Scheduled automations are turned off');
    },
    settingsPath() {
      if (this.betaUnavailable) return null;

      return (
        this.duoSettings?.duoScheduledTriggersSettingsPath ??
        this.duoSettings?.duoSettingsPath ??
        null
      );
    },
    body() {
      if (this.betaUnavailable) {
        return s__(
          'DuoAgentsPlatform|Existing schedules are kept but do not run, and new ones cannot be added. To run them again, turn on experiment and beta GitLab Duo features.',
        );
      }

      return this.$options.i18n.cannotChange;
    },
  },
  i18n: {
    canChange: s__(
      'DuoAgentsPlatform|Existing schedules are kept but do not run, and new ones cannot be added. To run them again, turn on scheduled automations in %{linkStart}GitLab Duo settings%{linkEnd}.',
    ),
    cannotChange: s__(
      'DuoAgentsPlatform|Existing schedules are kept but do not run, and new ones cannot be added. Ask a group Owner or administrator to turn them back on.',
    ),
  },
};
</script>

<template>
  <gl-alert
    v-if="show"
    variant="warning"
    :dismissible="false"
    :title="title"
    data-testid="scheduled-triggers-disabled-alert"
  >
    <gl-sprintf v-if="settingsPath" :message="$options.i18n.canChange">
      <template #link="{ content }">
        <gl-link :href="settingsPath">{{ content }}</gl-link>
      </template>
    </gl-sprintf>
    <template v-else>{{ body }}</template>
  </gl-alert>
</template>
