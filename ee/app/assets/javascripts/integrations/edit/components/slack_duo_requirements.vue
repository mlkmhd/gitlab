<script>
import { GlButton, GlIcon } from '@gitlab/ui';
import { uniqueId } from 'lodash-es';
import { s__, sprintf } from '~/locale';
import { REQUIREMENT_CHECKS } from '../slack_duo_copy';

// What GitLab Duo needs in the Duo group to answer in Slack. Fixes are links, never actions.
export default {
  name: 'SlackDuoRequirements',
  components: { GlButton, GlIcon },
  props: {
    requirements: {
      type: Array,
      required: true,
    },
    groupSettingsPath: {
      type: String,
      required: false,
      default: null,
    },
    instanceSettingsPath: {
      type: String,
      required: false,
      default: null,
    },
    // False while the Slack app needs reinstalling: the group is set up, but GitLab Duo can't answer yet.
    slackReady: {
      type: Boolean,
      required: false,
      default: true,
    },
  },
  data() {
    return {
      showRequirements: false,
      listId: uniqueId('slack-duo-requirements-'),
    };
  },
  computed: {
    failed() {
      return this.requirements.filter((requirement) => !requirement.ok);
    },
    listVisible() {
      return this.failed.length > 0 || this.showRequirements || !this.slackReady;
    },
    rows() {
      return this.requirements.map((requirement) => {
        const label = REQUIREMENT_CHECKS[requirement.ok ? 'passed' : 'failed'][requirement.id];
        const fix = requirement.ok ? null : this.fix(requirement, label);

        return { ...requirement, label, fix };
      });
    },
  },
  methods: {
    fix(requirement, name) {
      switch (requirement.fix) {
        case 'group_settings':
          return this.groupSettingsPath
            ? {
                text: s__('SlackIntegration|Open GitLab Duo settings'),
                ariaLabel: sprintf(
                  s__('SlackIntegration|Open GitLab Duo settings to fix: %{requirement}'),
                  { requirement: name },
                  false,
                ),
                href: this.groupSettingsPath,
              }
            : null;
        case 'instance_settings':
          return this.instanceSettingsPath
            ? {
                text: s__('SlackIntegration|Open instance settings'),
                ariaLabel: sprintf(
                  s__('SlackIntegration|Open instance settings to fix: %{requirement}'),
                  { requirement: name },
                  false,
                ),
                href: this.instanceSettingsPath,
              }
            : { hint: s__('SlackIntegration|Ask your administrator to change this.') };
        default:
          return null;
      }
    },
  },
};
</script>

<template>
  <div data-testid="slack-duo-requirements">
    <p v-if="!failed.length && slackReady" class="gl-mb-2 gl-flex gl-items-center gl-gap-2">
      <gl-icon name="check-circle-filled" variant="success" :aria-label="__('Passed')" />
      <span>{{
        s__('SlackIntegration|Ready. Members of the group can mention @GitLab in Slack.')
      }}</span>
      <gl-button
        category="tertiary"
        size="small"
        :aria-expanded="String(showRequirements)"
        :aria-controls="listId"
        data-testid="slack-duo-toggle-requirements"
        @click="showRequirements = !showRequirements"
        >{{
          showRequirements
            ? s__('SlackIntegration|Hide requirements')
            : s__('SlackIntegration|Show requirements')
        }}</gl-button
      >
    </p>
    <p v-else-if="failed.length" class="gl-mb-3 gl-font-bold">
      {{ s__("SlackIntegration|GitLab Duo can't answer in Slack until these are fixed:") }}
    </p>
    <ul v-show="listVisible" :id="listId" class="gl-m-0 gl-list-none gl-p-0">
      <li
        v-for="row in rows"
        :key="row.id"
        class="gl-mb-3 gl-flex gl-items-center gl-gap-3"
        :data-testid="`slack-duo-requirement-${row.id}`"
      >
        <gl-icon
          :name="row.ok ? 'check-circle-filled' : 'warning'"
          :variant="row.ok ? 'success' : 'warning'"
          :aria-label="row.ok ? __('Passed') : __('Needs attention')"
        />
        <span class="gl-grow">{{ row.label }}</span>
        <template v-if="row.fix">
          <gl-button
            v-if="row.fix.href"
            size="small"
            :href="row.fix.href"
            :aria-label="row.fix.ariaLabel"
            >{{ row.fix.text }}</gl-button
          >
          <span v-else class="gl-text-sm gl-text-subtle">{{ row.fix.hint }}</span>
        </template>
      </li>
    </ul>
  </div>
</template>
