<script>
import { GlAlert, GlSprintf } from '@gitlab/ui';

// Slack doesn't send mentions of @GitLab to an app without `app_mentions:read`.
export default {
  name: 'SlackDuoPermissionsAlert',
  components: {
    GlAlert,
    GlSprintf,
  },
  props: {
    teamName: {
      type: String,
      required: true,
    },
    reinstallPath: {
      type: String,
      required: false,
      default: null,
    },
  },
};
</script>

<template>
  <gl-alert
    variant="warning"
    :title="s__('SlackIntegration|Reinstall to use GitLab Duo in Slack')"
    :dismissible="false"
    :primary-button-text="
      reinstallPath ? s__('SlackIntegration|Reinstall GitLab for Slack app') : ''
    "
    :primary-button-link="reinstallPath || ''"
  >
    <gl-sprintf
      :message="
        s__(
          'SlackIntegration|The Slack app for %{workspace} is missing a permission GitLab Duo needs (reading mentions of @GitLab). Reinstall the app to grant it.',
        )
      "
    >
      <template #workspace>
        <strong>{{ teamName }}</strong>
      </template>
    </gl-sprintf>
  </gl-alert>
</template>
