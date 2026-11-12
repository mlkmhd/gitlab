<script>
import { GlAlert, GlBadge, GlCard, GlIcon, GlLink, GlLoadingIcon, GlSprintf } from '@gitlab/ui';
import * as Sentry from '~/sentry/sentry_browser_wrapper';
import {
  FLOW_STATUSES_READY,
  TRIAGE_PRESET_CAPABILITIES,
} from 'ee/security_configuration/constants';
import { isOffForGroup } from 'ee/security_configuration/components/scan_profiles/utils';
import groupTriageAndRemediationFlowStatusesQuery from 'ee/security_configuration/graphql/scan_profiles/group_triage_and_remediation_flow_statuses.query.graphql';

export default {
  name: 'EnableScannersReviewCapabilities',
  components: {
    GlAlert,
    GlBadge,
    GlCard,
    GlIcon,
    GlLink,
    GlLoadingIcon,
    GlSprintf,
  },
  inject: ['groupFullPath', 'rootGroupName', 'duoSettingsPath', 'groupOwnersPath', 'wizard'],
  data() {
    return {
      flowStatuses: [],
      hasError: false,
    };
  },
  apollo: {
    flowStatuses: {
      query: groupTriageAndRemediationFlowStatusesQuery,
      variables() {
        return { fullPath: this.groupFullPath };
      },
      update(data) {
        return data?.group?.triageAndRemediationFlowStatuses ?? [];
      },
      error(error) {
        this.hasError = true;
        Sentry.captureException(error);
      },
    },
  },
  computed: {
    isLoading() {
      return this.$apollo.queries.flowStatuses.loading;
    },
    presetTriggers() {
      return this.wizard.selectedProfiles[0]?.triggers ?? [];
    },
    presetCapabilities() {
      return TRIAGE_PRESET_CAPABILITIES.filter(({ triggerType }) =>
        this.presetTriggers.includes(triggerType),
      );
    },
    offCapabilities() {
      return this.presetCapabilities.filter((capability) =>
        isOffForGroup(this.findFlowStatus(capability)),
      );
    },
    readyCapabilities() {
      return this.presetCapabilities.filter((capability) =>
        FLOW_STATUSES_READY.includes(this.findFlowStatus(capability)?.flowStatus),
      );
    },
  },
  methods: {
    findFlowStatus({ triggerType }) {
      return this.flowStatuses.find((status) => status.triggerType === triggerType);
    },
  },
};
</script>
<template>
  <gl-loading-icon v-if="isLoading" size="lg" class="gl-my-5" />
  <gl-alert v-else-if="hasError" variant="danger" :dismissible="false">
    {{ s__('SecurityConfiguration|Could not check which capabilities can run. Try again later.') }}
  </gl-alert>
  <div
    v-else
    class="container-limited limit-container-width gl-mx-auto gl-flex gl-flex-col gl-gap-5"
  >
    <gl-card
      v-if="offCapabilities.length"
      header-class="gl-flex gl-items-center gl-justify-between gl-gap-3"
      body-class="gl-p-0"
      data-testid="off-capabilities-card"
    >
      <template #header>
        <strong>{{ s__("SecurityConfiguration|Won't run yet") }}</strong>
        <span class="gl-text-subtle" data-testid="capability-count">{{
          n__(
            'SecurityConfiguration|%d capability',
            'SecurityConfiguration|%d capabilities',
            offCapabilities.length,
          )
        }}</span>
      </template>
      <ul class="gl-m-0 gl-list-none gl-p-0">
        <li
          v-for="capability in offCapabilities"
          :key="capability.triggerType"
          class="gl-border-t gl-flex gl-items-center gl-gap-3 gl-px-5 gl-py-4 first:gl-border-t-0"
          data-testid="off-capability"
        >
          <gl-icon :name="capability.icon" />
          <div class="gl-flex gl-min-w-0 gl-grow gl-flex-col">
            <strong>{{ capability.title }}</strong>
            <span class="gl-text-subtle">
              <gl-sprintf
                v-if="duoSettingsPath"
                :message="
                  s__(
                    'SecurityConfiguration|Off for %{groupName}. Turn it on in GitLab Duo settings',
                  )
                "
              >
                <template #groupName>{{ rootGroupName }}</template>
              </gl-sprintf>
              <gl-sprintf
                v-else
                :message="s__('SecurityConfiguration|Waiting on the Owner of %{groupName}')"
              >
                <template #groupName>{{ rootGroupName }}</template>
              </gl-sprintf>
            </span>
          </div>
        </li>
      </ul>
      <template v-if="duoSettingsPath || groupOwnersPath" #footer>
        <gl-link v-if="duoSettingsPath" :href="duoSettingsPath" data-testid="duo-settings-link">{{
          s__('SecurityConfiguration|View GitLab Duo settings')
        }}</gl-link>
        <gl-sprintf
          v-else
          :message="
            s__('SecurityConfiguration|Ask a %{linkStart}group Owner%{linkEnd} to turn them on.')
          "
        >
          <template #link="{ content }">
            <gl-link :href="groupOwnersPath" data-testid="group-owners-link">{{ content }}</gl-link>
          </template>
        </gl-sprintf>
      </template>
    </gl-card>
    <gl-card
      v-if="readyCapabilities.length"
      header-class="gl-flex gl-items-center gl-justify-between gl-gap-3"
      body-class="gl-p-0"
      data-testid="ready-capabilities-card"
    >
      <template #header>
        <strong>{{ s__('SecurityConfiguration|Ready') }}</strong>
        <span class="gl-text-subtle" data-testid="capability-count">{{
          n__(
            'SecurityConfiguration|%d capability',
            'SecurityConfiguration|%d capabilities',
            readyCapabilities.length,
          )
        }}</span>
      </template>
      <ul class="gl-m-0 gl-list-none gl-p-0">
        <li
          v-for="capability in readyCapabilities"
          :key="capability.triggerType"
          class="gl-border-t gl-flex gl-items-center gl-gap-3 gl-px-5 gl-py-4 first:gl-border-t-0"
          data-testid="ready-capability"
        >
          <gl-icon :name="capability.icon" />
          <strong class="gl-min-w-0 gl-grow">{{ capability.title }}</strong>
          <gl-badge variant="success" icon="check" class="gl-shrink-0">
            {{ s__('SecurityConfiguration|No action needed') }}
          </gl-badge>
        </li>
      </ul>
    </gl-card>
  </div>
</template>
