<script>
import { GlAlert, GlSprintf } from '@gitlab/ui';
import * as Sentry from '~/sentry/sentry_browser_wrapper';
import HelpPageLink from '~/vue_shared/components/help_page_link/help_page_link.vue';
import serviceDeskEnabledQuery from '../graphql/service_desk_enabled.query.graphql';

export default {
  name: 'ServiceDeskEnabledAlert',
  components: {
    GlAlert,
    GlSprintf,
    HelpPageLink,
  },
  props: {
    fullPath: {
      type: String,
      required: false,
      default: '',
    },
  },
  data() {
    return {
      serviceDeskEnabled: undefined,
    };
  },
  apollo: {
    serviceDeskEnabled: {
      query: serviceDeskEnabledQuery,
      variables() {
        return {
          fullPath: this.fullPath,
        };
      },
      update(data) {
        return data?.project?.serviceDeskEnabled;
      },
      error(error) {
        Sentry.captureException(error);
      },
    },
  },
};
</script>

<template>
  <gl-alert
    v-if="serviceDeskEnabled === false"
    class="gl-mb-3"
    :dismissible="false"
    variant="warning"
  >
    <gl-sprintf
      :message="
        s__(
          'WorkItem|This project does not have %{linkStart}Service Desk%{linkEnd} enabled, so the user who created the issue will no longer receive email notifications about new activity.',
        )
      "
    >
      <template #link="{ content }">
        <help-page-link href="user/project/service_desk/_index.md">
          {{ content }}
        </help-page-link>
      </template>
    </gl-sprintf>
  </gl-alert>
</template>
