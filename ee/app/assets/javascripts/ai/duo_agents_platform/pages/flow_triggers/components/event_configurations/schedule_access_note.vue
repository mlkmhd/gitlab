<script>
import { GlSprintf } from '@gitlab/ui';
import { s__ } from '~/locale';
import HelpPageLink from '~/vue_shared/components/help_page_link/help_page_link.vue';

export default {
  name: 'ScheduleAccessNote',
  components: {
    GlSprintf,
    HelpPageLink,
  },
  props: {
    serviceAccountRole: {
      type: String,
      required: false,
      default: null,
    },
  },
  computed: {
    message() {
      return this.serviceAccountRole
        ? s__(
            `DuoAgentsPlatform|Scheduled automations use a separate service account with the %{linkStart}%{role} role%{linkEnd} on this project and no composite identity, so they can do anything that role allows. The account's role follows the flow's service account role: it's lowered automatically before each run, and raised only when someone who can assign that role edits this automation. %{docsStart}Learn more%{docsEnd}.`,
          )
        : s__(
            `DuoAgentsPlatform|Scheduled automations use a separate service account with no composite identity, so they can do anything its role allows. The account's role follows the flow's service account role: it's lowered automatically before each run, and raised only when someone who can assign that role edits this automation. %{docsStart}Learn more%{docsEnd}.`,
          );
    },
  },
  roleLinkText: s__('DuoAgentsPlatform|%{role} role'),
};
</script>

<template>
  <span>
    <gl-sprintf :message="message">
      <template #link>
        <help-page-link href="user/permissions" anchor="roles">
          <gl-sprintf :message="$options.roleLinkText">
            <template #role>{{ serviceAccountRole }}</template>
          </gl-sprintf>
        </help-page-link>
      </template>
      <template #docs="{ content }">
        <help-page-link
          href="user/duo_agent_platform/triggers/_index"
          anchor="service-account-for-scheduled-automations"
          >{{ content }}</help-page-link
        >
      </template>
    </gl-sprintf>
  </span>
</template>
