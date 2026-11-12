<script>
import {
  GlBadge,
  GlButton,
  GlIcon,
  GlLink,
  GlPopover,
  GlSkeletonLoader,
  GlSprintf,
  GlTruncate,
} from '@gitlab/ui';
import * as Sentry from '~/sentry/sentry_browser_wrapper';
import { BV_HIDE_POPOVER } from '~/lib/utils/constants';
import { s__ } from '~/locale';
import { SCAN_PROFILE_TYPE_TRIAGE_AND_REMEDIATION } from '~/security_configuration/constants';
import {
  TRIAGE_CAPABILITY_STATUS_OFF_FOR_GROUP,
  TRIAGE_PRESET_CAPABILITIES,
  TRIAGE_RUN_MODE_LABELS,
} from 'ee/security_configuration/constants';
import { isOffForGroup } from 'ee/security_configuration/components/scan_profiles/utils';
import {
  SECURITY_CONFIGURATION_PATH,
  TOOL_NOT_ENABLED,
  TRIAGE_CAPABILITY_ANALYZER_TYPES,
} from '../constants';
import { isSubGroup } from '../utils';
import ProjectSecurityScanProfilesQuery from '../graphql/project_security_scan_profiles.query.graphql';
import GroupCapabilitiesIndicator from './group_capabilities_indicator.vue';

export default {
  name: 'CapabilitiesCell',
  components: {
    GlBadge,
    GlButton,
    GlIcon,
    GlLink,
    GlPopover,
    GlSkeletonLoader,
    GlSprintf,
    GlTruncate,
    GroupCapabilitiesIndicator,
  },
  inject: {
    canApplyProfiles: {},
    canAdminRootGroup: { default: false },
    duoSettingsPath: { default: '' },
    groupOwnersPath: { default: '' },
  },
  props: {
    item: {
      type: Object,
      required: true,
    },
    hideProfileActions: {
      type: Boolean,
      required: false,
      default: false,
    },
  },
  emits: ['open-triage-drawer'],
  data() {
    return {
      popoverShown: false,
      securityScanProfiles: [],
    };
  },
  apollo: {
    securityScanProfiles: {
      query: ProjectSecurityScanProfilesQuery,
      variables() {
        return { fullPath: this.item.fullPath };
      },
      fetchPolicy: 'cache-and-network',
      skip() {
        return !this.hasEnabledCapability || !this.popoverShown;
      },
      update: (data) => data.project?.securityScanProfiles || [],
      error(error) {
        Sentry.captureException(error);
      },
    },
  },
  computed: {
    isSubGroup() {
      return isSubGroup(this.item);
    },
    badgeId() {
      return `capabilities-${this.item.fullPath.replaceAll('/', '-')}`;
    },
    coverage() {
      return this.item.triageAndRemediationCoverage?.capabilities || [];
    },
    enabledCapabilities() {
      return TRIAGE_PRESET_CAPABILITIES.map(({ triggerType }) =>
        this.coverage.find((entry) => entry.triggerType === triggerType && entry.enabled),
      ).filter(Boolean);
    },
    hasEnabledCapability() {
      return this.enabledCapabilities.length > 0;
    },
    isEnabled() {
      return this.enabledCapabilities.some((capability) => !isOffForGroup(capability));
    },
    allEnabledOffForGroup() {
      return this.hasEnabledCapability && !this.isEnabled;
    },
    needsAttention() {
      return (
        this.isEnabled &&
        this.enabledCapabilities.some(
          (capability) => !isOffForGroup(capability) && this.isScannerOff(capability),
        )
      );
    },
    badgeLabel() {
      if (this.needsAttention) return this.$options.i18n.needsAttention;
      return this.isEnabled ? this.$options.i18n.enabled : this.$options.i18n.notEnabled;
    },
    badgeStyling() {
      if (this.needsAttention) {
        return { variant: 'warning', class: 'gl-border-transparent' };
      }
      if (this.isEnabled) {
        return { variant: 'success', class: 'gl-border-transparent' };
      }
      return {
        variant: 'neutral',
        class: '!gl-bg-default !gl-text-neutral-600 gl-border-gray-200 gl-border-dashed',
      };
    },
    isProfileLoading() {
      return this.$apollo.queries.securityScanProfiles.loading;
    },
    triageProfile() {
      return this.securityScanProfiles.find(
        ({ scanType }) => scanType === SCAN_PROFILE_TYPE_TRIAGE_AND_REMEDIATION,
      );
    },
    profileName() {
      return this.triageProfile?.name;
    },
    manageConfigurationHref() {
      return `${this.item.webPath}${SECURITY_CONFIGURATION_PATH}?tab=automated-triage-and-remediation`;
    },
    capabilityRows() {
      return TRIAGE_PRESET_CAPABILITIES.map(({ triggerType, title }) => {
        const capability = this.coverage.find((entry) => entry.triggerType === triggerType);
        const isOn = Boolean(capability?.enabled);
        const offForGroup = isOn && isOffForGroup(capability);
        return {
          triggerType,
          title,
          status: this.statusText(capability),
          offForGroup,
          scannerOff: isOn && !offForGroup && this.isScannerOff(capability),
        };
      });
    },
  },
  methods: {
    isScannerOff({ triggerType }) {
      const analyzerTypes = TRIAGE_CAPABILITY_ANALYZER_TYPES[triggerType];
      if (!analyzerTypes) return false;

      return !(this.item.analyzerStatuses ?? []).some(
        ({ analyzerType, status }) =>
          analyzerTypes.includes(analyzerType) && status !== TOOL_NOT_ENABLED,
      );
    },
    statusText(capability) {
      if (!capability?.enabled) return this.$options.i18n.off;
      return TRIAGE_RUN_MODE_LABELS[capability.runMode] ?? '';
    },
    openTriageDrawer() {
      this.$root.$emit(BV_HIDE_POPOVER, this.badgeId);
      this.$emit('open-triage-drawer', {
        project: this.item,
        presetId: this.triageProfile?.id ?? '',
      });
    },
  },
  offForGroupStatus: TRIAGE_CAPABILITY_STATUS_OFF_FOR_GROUP,
  i18n: {
    name: s__('SecurityInventory|Automated Triage and Remediation'),
    enabled: s__('SecurityInventory|Automated Triage and Remediation enabled'),
    notEnabled: s__('SecurityInventory|Automated Triage and Remediation not enabled'),
    needsAttention: s__('SecurityInventory|Automated Triage and Remediation needs attention'),
    scannerNotEnabled: s__('SecurityInventory|Scanner not enabled'),
    notEnabledDescription: s__(
      "SecurityInventory|Automated Triage and Remediation isn't acting on vulnerabilities in this project. Apply a profile to turn it on.",
    ),
    profile: s__('SecurityInventory|Profile'),
    off: s__('SecurityInventory|Off'),
    askGroupOwner: s__(
      'SecurityInventory|Ask a %{linkStart}group Owner%{linkEnd} to turn them on.',
    ),
    turnOnInDuoSettings: s__('SecurityInventory|Turn them on in GitLab Duo settings'),
  },
};
</script>

<template>
  <group-capabilities-indicator v-if="isSubGroup" :item="item" />
  <div v-else>
    <gl-badge
      :id="badgeId"
      tag="button"
      type="button"
      v-bind="badgeStyling"
      :aria-label="badgeLabel"
      class="gl-border gl-max-w-18 gl-text-xs gl-font-bold focus-visible:gl-focus"
      data-testid="capabilities-badge"
    >
      <gl-truncate :text="$options.i18n.name" />
    </gl-badge>
    <gl-popover
      :target="badgeId"
      placement="top"
      :title="$options.i18n.name"
      :css-classes="hasEnabledCapability ? ['gl-max-w-48'] : []"
      @show="popoverShown = true"
      @hidden="popoverShown = false"
    >
      <div v-if="hasEnabledCapability" class="gl-flex gl-flex-col gl-gap-3">
        <div
          v-if="isProfileLoading || profileName"
          class="gl-border-b gl-flex gl-items-center gl-justify-between gl-gap-5 gl-pb-3"
          data-testid="profile-row"
        >
          <span class="gl-shrink-0">{{ $options.i18n.profile }}</span>
          <gl-skeleton-loader v-if="isProfileLoading" :width="120" :lines="1" equal-width-lines />
          <gl-truncate v-else :text="profileName" class="gl-min-w-0 gl-font-bold" with-tooltip />
        </div>
        <ul class="gl-m-0 gl-flex gl-list-none gl-flex-col gl-gap-2 gl-p-0">
          <li
            v-for="row in capabilityRows"
            :key="row.triggerType"
            class="gl-flex gl-items-start gl-justify-between gl-gap-5"
            data-testid="capability-row"
          >
            <span>{{ row.title }}</span>
            <span
              v-if="row.offForGroup"
              class="gl-flex gl-items-center gl-gap-2 gl-font-bold"
              data-testid="off-for-group-status"
            >
              <gl-icon :name="$options.offForGroupStatus.icon" variant="warning" />
              {{ $options.offForGroupStatus.label }}
            </span>
            <span
              v-else-if="row.scannerOff"
              class="gl-flex gl-shrink-0 gl-items-center gl-gap-2 gl-whitespace-nowrap gl-text-subtle"
              data-testid="scanner-off-status"
            >
              <gl-icon name="clear" variant="subtle" />
              {{ $options.i18n.scannerNotEnabled }}
            </span>
            <span v-else-if="row.status" class="gl-font-bold">{{ row.status }}</span>
            <span v-else class="gl-text-subtle">&ndash;</span>
          </li>
        </ul>
        <p v-if="allEnabledOffForGroup" class="gl-mb-0" data-testid="off-for-group-footer">
          <gl-link
            v-if="canAdminRootGroup && duoSettingsPath"
            :href="duoSettingsPath"
            data-testid="duo-settings-link"
          >
            {{ $options.i18n.turnOnInDuoSettings }}
          </gl-link>
          <gl-sprintf v-else-if="!canAdminRootGroup" :message="$options.i18n.askGroupOwner">
            <template #link="{ content }">
              <gl-link :href="groupOwnersPath" data-testid="group-owners-link">{{
                content
              }}</gl-link>
            </template>
          </gl-sprintf>
        </p>
        <div v-if="canApplyProfiles" class="gl-flex gl-flex-wrap gl-gap-2">
          <gl-button
            v-if="!hideProfileActions"
            variant="confirm"
            size="small"
            :loading="isProfileLoading"
            class="gl-grow"
            data-testid="change-profile-button"
            @click="openTriageDrawer"
          >
            {{ s__('SecurityInventory|Change profile') }}
          </gl-button>
          <gl-button
            :href="manageConfigurationHref"
            size="small"
            class="gl-grow"
            data-testid="manage-configuration-button"
          >
            {{ s__('SecurityInventory|Manage configuration') }}
          </gl-button>
        </div>
      </div>
      <div v-else class="gl-flex gl-flex-col gl-gap-3">
        <p class="gl-mb-0" data-testid="not-enabled-description">
          {{ $options.i18n.notEnabledDescription }}
        </p>
        <gl-button
          v-if="canApplyProfiles && !hideProfileActions"
          block
          data-testid="apply-profile-button"
          @click="openTriageDrawer"
        >
          {{ s__('SecurityInventory|Apply profile') }}
        </gl-button>
      </div>
    </gl-popover>
  </div>
</template>
