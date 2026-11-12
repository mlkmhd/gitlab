<script>
import { GlButton, GlEmptyState, GlLink, GlSkeletonLoader, GlSprintf, GlTable } from '@gitlab/ui';
import EMPTY_SECURE_SVG from '@gitlab/svgs/dist/illustrations/empty-state/empty-secure-add-md.svg?url';
import { __, s__, n__, sprintf } from '~/locale';
import { createAlert } from '~/alert';
import * as Sentry from '~/sentry/sentry_browser_wrapper';
import { SCAN_PROFILE_TYPE_TRIAGE_AND_REMEDIATION } from '~/security_configuration/constants';
import {
  SEVERITY_LEVEL_CRITICAL,
  SEVERITY_LEVEL_INFO,
  SEVERITY_LEVELS,
  SEVERITY_LEVELS_GRAPHQL,
} from 'ee/security_dashboard/constants';
import {
  TRIAGE_PRESET_CAPABILITIES,
  TRIAGE_RUN_MODE_MANUAL,
} from 'ee/security_configuration/constants';
import SegmentedBar from 'ee/security_inventory/components/segmented_bar.vue';
import groupAvailableSecurityScanProfilesQuery from 'ee/security_configuration/graphql/scan_profiles/group_available_security_scan_profiles.query.graphql';
import groupSecurityPostureCountersQuery from 'ee/security_configuration/graphql/scan_profiles/group_security_posture_counters.query.graphql';
import groupTriageAndRemediationFlowStatusesQuery from 'ee/security_configuration/graphql/scan_profiles/group_triage_and_remediation_flow_statuses.query.graphql';
import { ROUTE_ENABLE_TRIAGE_AND_REMEDIATION } from '../enable_scanners_wizard/constants';
import { getDefaultProfile, getTriagePresets, isOffForGroup } from './utils';
import StatisticsCardRow from './statistics_card_row.vue';
import TriageProfileDrawer from './triage_profile_drawer.vue';

const TH_CLASS = '!gl-bg-strong !gl-border-0 gl-w-1/3 [.gl-table_&:hover]:!gl-bg-strong';
const TD_CLASS = '!gl-border-t-0';

const isCapability = (type) =>
  TRIAGE_PRESET_CAPABILITIES.some(({ triggerType }) => triggerType === type);

const capabilityCount = ({ triggers }) => triggers.filter((type) => isCapability(type)).length;

const onDemandCount = ({ triggerSettings }) =>
  triggerSettings.filter(
    ({ triggerType, configuration }) =>
      isCapability(triggerType) && configuration?.runMode === TRIAGE_RUN_MODE_MANUAL,
  ).length;

const PROFILE_FIELD = {
  key: 'profile',
  label: s__('SecurityConfiguration|Profile'),
  tdClass: TD_CLASS,
  thClass: `${TH_CLASS} gl-rounded-l-xl`,
};
const COVERAGE_FIELD = {
  key: 'coverage',
  label: s__('SecurityConfiguration|Project coverage'),
  tdClass: TD_CLASS,
  thClass: TH_CLASS,
};
const ACTIONS_FIELD = {
  key: 'actions',
  label: '',
  tdClass: `${TD_CLASS} gl-text-right`,
  thClass: `${TH_CLASS} gl-rounded-r-xl`,
};

export default {
  name: 'GroupTriageAndRemediationOverview',
  components: {
    GlButton,
    GlEmptyState,
    GlLink,
    GlSkeletonLoader,
    GlSprintf,
    GlTable,
    SegmentedBar,
    StatisticsCardRow,
    TriageProfileDrawer,
  },
  inject: {
    groupFullPath: {},
    securityInventoryPath: {},
    duoSettingsPath: {},
    groupOwnersPath: { default: '' },
    canApplyProfiles: {},
  },
  apollo: {
    presets: {
      query: groupAvailableSecurityScanProfilesQuery,
      variables() {
        return { fullPath: this.groupFullPath, gitlabRecommended: true };
      },
      update: (data) => getTriagePresets(data?.group?.availableSecurityScanProfiles ?? []),
      error(error) {
        this.handleError(
          error,
          s__('SecurityConfiguration|Failed to load triage and remediation profiles.'),
        );
      },
    },
    securityPostureCounters: {
      query: groupSecurityPostureCountersQuery,
      fetchPolicy: 'cache-and-network',
      variables() {
        return { fullPath: this.groupFullPath };
      },
      update: (data) => data?.group?.securityPostureCounters ?? {},
      error(error) {
        this.hasCountersError = true;
        this.handleError(error, s__('SecurityConfiguration|Failed to load project coverage.'));
      },
    },
    flowStatuses: {
      query: groupTriageAndRemediationFlowStatusesQuery,
      fetchPolicy: 'cache-and-network',
      variables() {
        return { fullPath: this.groupFullPath };
      },
      update: (data) => data?.group?.triageAndRemediationFlowStatuses ?? null,
      error(error) {
        this.hasFlowStatusesError = true;
        this.handleError(error, s__('SecurityConfiguration|Failed to load capability statuses.'));
      },
    },
  },
  data() {
    return {
      presets: [],
      securityPostureCounters: {},
      hasCountersError: false,
      flowStatuses: null,
      hasFlowStatusesError: false,
      selectedPresetId: '',
      isDrawerOpen: false,
    };
  },
  computed: {
    isSubgroup() {
      return this.groupFullPath.includes('/');
    },
    fields() {
      return this.isSubgroup
        ? [PROFILE_FIELD, ACTIONS_FIELD]
        : [PROFILE_FIELD, COVERAGE_FIELD, ACTIONS_FIELD];
    },
    sortedPresets() {
      const standard = getDefaultProfile(SCAN_PROFILE_TYPE_TRIAGE_AND_REMEDIATION, this.presets);
      return [...this.presets].sort(
        (a, b) =>
          Number(b === standard) - Number(a === standard) || b.projectCount - a.projectCount,
      );
    },
    isLoading() {
      return this.$apollo.queries.presets.loading;
    },
    areCountersLoading() {
      return this.$apollo.queries.securityPostureCounters.loading;
    },
    hasNoCoverage() {
      return !this.areCountersLoading && this.securityPostureCounters.withTriageCoverage === 0;
    },
    hasCoverage() {
      return this.securityPostureCounters.withTriageCoverage > 0;
    },
    totalProjectsCount() {
      return this.securityPostureCounters.total ?? 0;
    },
    areCardsLoading() {
      return this.areCountersLoading || this.$apollo.queries.flowStatuses.loading;
    },
    offForGroupNames() {
      return TRIAGE_PRESET_CAPABILITIES.filter(({ triggerType }) =>
        this.flowStatuses?.some(
          (status) => status.triggerType === triggerType && isOffForGroup(status),
        ),
      ).map(({ title }) => title);
    },
    offForGroupItems() {
      return this.offForGroupNames.length ? this.offForGroupNames : [__('None')];
    },
    hasNoFlowStatuses() {
      return this.hasFlowStatusesError || !this.flowStatuses;
    },
    capabilitiesDescription() {
      if (this.hasNoFlowStatuses || this.offForGroupNames.length) return null;

      return s__('SecurityConfiguration|Every capability can run');
    },
    capabilitiesLink() {
      if (!this.duoSettingsPath && this.offForGroupNames.length) {
        return {
          linkMessage: s__(
            'SecurityConfiguration|Ask a %{linkStart}group Owner%{linkEnd} to turn them on.',
          ),
          href: this.groupOwnersPath,
        };
      }

      return {
        linkText: s__('SecurityConfiguration|GitLab Duo settings'),
        href: this.duoSettingsPath,
      };
    },
    statCards() {
      const withoutProfileCount = Math.max(
        this.totalProjectsCount - (this.securityPostureCounters.withTriageCoverage ?? 0),
        0,
      );

      return [
        {
          title: s__('SecurityConfiguration|Projects without a profile'),
          value: this.hasCountersError ? __('—') : withoutProfileCount,
          description: this.hasCountersError
            ? null
            : s__('SecurityConfiguration|Have no Automated Triage and Remediation profile'),
          linkText: s__('SecurityConfiguration|View in Security inventory'),
          href: this.securityInventoryPath,
        },
        {
          title: s__('SecurityConfiguration|Capabilities off for group'),
          info: s__(
            "SecurityConfiguration|Off for group, so they don't run on any project until turned on",
          ),
          value: __('—'),
          items: this.hasNoFlowStatuses ? null : this.offForGroupItems,
          description: this.capabilitiesDescription,
          ...this.capabilitiesLink,
        },
      ];
    },
  },
  methods: {
    summary(preset) {
      const capabilities = n__(
        'SecurityConfiguration|%d capability',
        'SecurityConfiguration|%d capabilities',
        capabilityCount(preset),
      );
      const severities = preset.triggerSettings
        .filter(({ triggerType }) => isCapability(triggerType))
        .map(({ configuration }) => SEVERITY_LEVELS_GRAPHQL.indexOf(configuration?.severityLevel))
        .filter((index) => index >= 0);
      if (!severities.length) return capabilities;

      const lowestSeverity = SEVERITY_LEVELS_GRAPHQL[Math.max(...severities)].toLowerCase();
      if (lowestSeverity === SEVERITY_LEVEL_INFO) {
        return sprintf(s__('SecurityConfiguration|All severities · %{capabilities}'), {
          capabilities,
        });
      }
      if (lowestSeverity === SEVERITY_LEVEL_CRITICAL) {
        return sprintf(s__('SecurityConfiguration|Critical severity only · %{capabilities}'), {
          capabilities,
        });
      }
      return sprintf(
        s__('SecurityConfiguration|%{severity} severity and above · %{capabilities}'),
        {
          severity: SEVERITY_LEVELS[lowestSeverity],
          capabilities,
        },
      );
    },
    runMode(preset) {
      const manualCount = onDemandCount(preset);
      const total = capabilityCount(preset);

      if (!manualCount) return s__('SecurityConfiguration|All capabilities automatic');
      if (manualCount === total) return s__('SecurityConfiguration|All capabilities on demand');
      return sprintf(
        n__(
          'SecurityConfiguration|%{manualCount} of %{total} capability on demand',
          'SecurityConfiguration|%{manualCount} of %{total} capabilities on demand',
          total,
        ),
        { manualCount, total },
      );
    },
    coverageSegments(preset) {
      if (this.hasCountersError) return [];

      const { projectCount } = preset;
      return [
        {
          class: onDemandCount(preset) ? 'gl-bg-orange-200' : 'gl-bg-green-500',
          count: projectCount,
        },
        {
          class: 'gl-bg-status-neutral',
          count: Math.max(this.totalProjectsCount - projectCount, 0),
        },
      ];
    },
    coveragePercentage({ projectCount }) {
      if (this.hasCountersError) return __('—');

      return this.totalProjectsCount === 0
        ? '0%'
        : `${Math.round((projectCount / this.totalProjectsCount) * 100)}%`;
    },
    coverageDetails(preset) {
      const { projectCount } = preset;
      return sprintf(s__('SecurityConfiguration|%{projects} · %{runMode}'), {
        projects: projectCount
          ? n__('%d project', '%d projects', projectCount)
          : s__('SecurityConfiguration|Not applied'),
        runMode: this.runMode(preset),
      });
    },
    openDrawer(presetId) {
      this.selectedPresetId = presetId;
      this.isDrawerOpen = true;
    },
    handleError(error, message) {
      createAlert({ message });
      Sentry.captureException(error);
    },
  },
  EMPTY_SECURE_SVG,
  ROUTE_ENABLE_TRIAGE_AND_REMEDIATION,
};
</script>

<template>
  <gl-empty-state
    v-if="hasNoCoverage"
    :svg-path="$options.EMPTY_SECURE_SVG"
    :svg-height="144"
    :title="s__('SecurityConfiguration|Stop triaging vulnerabilities by hand')"
    :description="
      s__(
        'SecurityConfiguration|Apply a profile and GitLab opens fix merge requests, flags likely false positives, and adds risk context, within limits you set.',
      )
    "
  >
    <template #actions>
      <gl-button
        v-if="canApplyProfiles"
        variant="confirm"
        :to="{ name: $options.ROUTE_ENABLE_TRIAGE_AND_REMEDIATION }"
        data-testid="triage-and-remediation-get-started-button"
      >
        {{ s__('SecurityConfiguration|Get started') }}
      </gl-button>
    </template>
  </gl-empty-state>
  <div v-else>
    <div class="gl-mb-4 gl-mt-3 gl-flex gl-items-baseline gl-justify-between">
      <span data-testid="triage-and-remediation-description">
        <gl-sprintf
          :message="
            s__(
              'SecurityConfiguration|Open fix merge requests, flag likely false positives, and add context to new findings across your projects. To see capabilities by project, visit the %{linkStart}Security inventory%{linkEnd}.',
            )
          "
        >
          <template #link="{ content }">
            <gl-link :href="securityInventoryPath">{{ content }}</gl-link>
          </template>
        </gl-sprintf>
      </span>
      <gl-button
        v-if="canApplyProfiles && hasCoverage"
        class="gl-shrink-0"
        variant="confirm"
        :to="{ name: $options.ROUTE_ENABLE_TRIAGE_AND_REMEDIATION }"
        data-testid="apply-profile-button"
      >
        {{ s__('SecurityConfiguration|Apply profile') }}
      </gl-button>
    </div>

    <statistics-card-row :cards="statCards" :loading="areCardsLoading" />

    <gl-table
      :fields="fields"
      :items="sortedPresets"
      :busy="isLoading"
      table-class="gl-border-separate gl-border-spacing-0"
      tbody-tr-class="[&:last-child>td]:!gl-border-b-0"
    >
      <template #cell(profile)="{ item }">
        <div class="gl-flex gl-flex-col gl-gap-1">
          <span class="gl-font-bold" data-testid="profile-name">{{ item.name }}</span>
          <span class="gl-text-sm gl-text-subtle" data-testid="profile-summary">
            {{ summary(item) }}
          </span>
        </div>
      </template>
      <template #cell(coverage)="{ item }">
        <gl-skeleton-loader
          v-if="areCountersLoading"
          :width="300"
          :height="10"
          preserve-aspect-ratio="none"
        >
          <rect x="0" y="0" width="300" height="10" rx="5" />
        </gl-skeleton-loader>
        <div v-else class="gl-flex gl-flex-col gl-gap-1">
          <segmented-bar :segments="coverageSegments(item)" />
          <div class="gl-flex gl-justify-between gl-gap-2 gl-text-sm gl-text-subtle">
            <span data-testid="coverage-percentage">{{ coveragePercentage(item) }}</span>
            <span data-testid="coverage-details">{{ coverageDetails(item) }}</span>
          </div>
        </div>
      </template>
      <template #cell(actions)="{ item }">
        <gl-button data-testid="view-details-button" @click="openDrawer(item.id)">
          {{ __('View details') }}
        </gl-button>
      </template>
    </gl-table>

    <triage-profile-drawer
      :open="isDrawerOpen"
      :preset-id="selectedPresetId"
      @close="isDrawerOpen = false"
    />
  </div>
</template>
