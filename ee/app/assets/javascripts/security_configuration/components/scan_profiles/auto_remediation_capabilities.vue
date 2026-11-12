<script>
import { GlBadge, GlIcon, GlLink, GlSprintf, GlTableLite } from '@gitlab/ui';
import { n__, s__ } from '~/locale';
import {
  SBOM_INGESTED,
  TRIAGE_CAPABILITY_MARKERS,
  TRIAGE_CAPABILITY_STATUS_OFF_FOR_GROUP,
  TRIAGE_DEPENDENCY_SEVERITY_SCOPES,
  TRIAGE_PRESET_CAPABILITIES,
  TRIAGE_RUN_MODE_LABELS,
  TRIAGE_SEVERITY_SCOPES,
  TRIAGE_UPGRADE_POLICIES,
} from 'ee/security_configuration/constants';
import { triageCapabilityStatus } from './utils';

const hasValue = (value) => value !== null && value !== undefined;

const capabilityLimits = ({ openMergeRequestsLimit, upgradePolicy, cooldown }) =>
  [
    hasValue(openMergeRequestsLimit) &&
      n__(
        'SecurityConfiguration|Up to %d open MR',
        'SecurityConfiguration|Up to %d open MRs',
        openMergeRequestsLimit,
      ),
    TRIAGE_UPGRADE_POLICIES[upgradePolicy],
    cooldown > 0 &&
      n__(
        'SecurityConfiguration|%d-day cooldown',
        'SecurityConfiguration|%d-day cooldown',
        cooldown,
      ),
  ]
    .filter(Boolean)
    .join(', ');

export default {
  name: 'AutoRemediationCapabilities',
  components: {
    GlBadge,
    GlIcon,
    GlLink,
    GlSprintf,
    GlTableLite,
  },
  inject: {
    rootGroupName: { default: '' },
    canAdminRootGroup: { default: false },
    duoSettingsPath: { default: '' },
    groupOwnersPath: { default: '' },
  },
  props: {
    profile: {
      type: Object,
      required: true,
    },
    capabilities: {
      type: Array,
      required: false,
      default: () => [],
    },
  },
  computed: {
    rows() {
      return TRIAGE_PRESET_CAPABILITIES.filter(({ triggerType }) =>
        this.profile.triggers.includes(triggerType),
      ).map(({ triggerType, title, icon }) => {
        const coverage = this.capabilities.find((item) => item.triggerType === triggerType);
        const configuration =
          this.profile.triggerSettings?.find((setting) => setting.triggerType === triggerType)
            ?.configuration ?? {};
        const severityScopes =
          triggerType === SBOM_INGESTED
            ? TRIAGE_DEPENDENCY_SEVERITY_SCOPES
            : TRIAGE_SEVERITY_SCOPES;

        return {
          triggerType,
          title,
          icon,
          ...TRIAGE_CAPABILITY_MARKERS[triggerType],
          status: triageCapabilityStatus(coverage),
          severity: severityScopes[configuration.severityLevel] ?? '',
          runMode: coverage?.enabled ? (TRIAGE_RUN_MODE_LABELS[configuration.runMode] ?? '') : '',
          limits: capabilityLimits(configuration),
        };
      });
    },
    hasCapabilityOffForGroup() {
      return this.rows.some(({ status }) => status === TRIAGE_CAPABILITY_STATUS_OFF_FOR_GROUP);
    },
  },
  fields: [
    { key: 'capability', label: s__('SecurityConfiguration|Capability') },
    { key: 'status', label: s__('SecurityConfiguration|Status'), tdClass: 'gl-whitespace-nowrap' },
    {
      key: 'severity',
      label: s__('SecurityConfiguration|Severity'),
      tdClass: 'gl-whitespace-nowrap',
    },
    {
      key: 'runMode',
      label: s__('SecurityConfiguration|Run mode'),
      tdClass: 'gl-whitespace-nowrap',
    },
    { key: 'limits', label: s__('SecurityConfiguration|Limits') },
  ],
};
</script>

<template>
  <section class="gl-mt-7" data-testid="auto-remediation-capabilities">
    <h2 class="gl-mb-3 gl-mt-0 gl-text-size-h2">
      {{ s__('SecurityConfiguration|Capabilities') }}
    </h2>
    <p>
      {{
        sprintf(
          s__(
            'SecurityConfiguration|What %{profileName} does in this project, and whether each capability runs.',
          ),
          { profileName: profile.name },
        )
      }}
    </p>
    <gl-table-lite :items="rows" :fields="$options.fields" primary-key="triggerType">
      <template #cell(capability)="{ item }">
        <span class="gl-flex gl-items-center gl-gap-3">
          <gl-icon :name="item.icon" :size="16" variant="subtle" />
          {{ item.title }}
          <gl-icon
            v-if="item.ai"
            name="tanuki-ai"
            :size="14"
            variant="subtle"
            :aria-label="s__('SecurityConfiguration|Uses GitLab Duo')"
            data-testid="capability-ai-icon"
          />
          <gl-badge v-if="item.beta" variant="neutral" data-testid="capability-beta-badge">
            {{ __('Beta') }}
          </gl-badge>
        </span>
      </template>
      <template #cell(status)="{ item }">
        <span class="gl-flex gl-items-center gl-gap-2" data-testid="capability-status">
          <gl-icon :name="item.status.icon" :size="14" :variant="item.status.variant" />
          {{ item.status.label }}
        </span>
      </template>
      <template #cell(severity)="{ item }">
        <span v-if="item.severity" data-testid="capability-severity">{{ item.severity }}</span>
        <span v-else class="gl-text-subtle">&ndash;</span>
      </template>
      <template #cell(runMode)="{ item }">
        <span v-if="item.runMode">{{ item.runMode }}</span>
        <span v-else class="gl-text-subtle">&ndash;</span>
      </template>
      <template #cell(limits)="{ item }">
        <span v-if="item.limits" data-testid="capability-limits">{{ item.limits }}</span>
        <span v-else class="gl-text-subtle">&ndash;</span>
      </template>
    </gl-table-lite>
    <p
      v-if="hasCapabilityOffForGroup"
      class="gl-mb-0 gl-mt-4 gl-text-subtle"
      data-testid="off-for-group-note"
    >
      <gl-sprintf
        :message="
          s__(
            'SecurityConfiguration|Capabilities an Owner turned off for %{groupName} don\'t run, and a profile doesn\'t turn them back on.',
          )
        "
      >
        <template #groupName>{{ rootGroupName }}</template>
      </gl-sprintf>
      <gl-link
        v-if="canAdminRootGroup && duoSettingsPath"
        :href="duoSettingsPath"
        data-testid="duo-settings-link"
      >
        {{ s__('SecurityConfiguration|Turn them on in GitLab Duo settings') }}
      </gl-link>
      <gl-sprintf
        v-else-if="!canAdminRootGroup"
        :message="
          s__('SecurityConfiguration|Ask a %{linkStart}group Owner%{linkEnd} to turn them on.')
        "
      >
        <template #link="{ content }">
          <gl-link :href="groupOwnersPath" data-testid="group-owners-link">{{ content }}</gl-link>
        </template>
      </gl-sprintf>
    </p>
  </section>
</template>
