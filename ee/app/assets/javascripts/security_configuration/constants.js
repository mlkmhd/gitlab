import { s__ } from '~/locale';
import {
  featureToMutationMap as featureToMutationMapCE,
  SCAN_PROFILE_SCANNER_HEALTH_ACTIVE,
  SCAN_PROFILE_SCANNER_HEALTH_FAILED,
  SCAN_PROFILE_SCANNER_HEALTH_PENDING,
  SCAN_PROFILE_SCANNER_HEALTH_STALE,
  SCAN_PROFILE_SCANNER_HEALTH_UNCONFIGURED,
  SCAN_PROFILE_SCANNER_HEALTH_WARNING,
} from '~/security_configuration/constants';
import {
  REPORT_TYPE_DEPENDENCY_SCANNING,
  REPORT_TYPE_CONTAINER_SCANNING,
} from '~/vue_shared/security_reports/constants';
import configureDependencyScanningMutation from './graphql/configure_dependency_scanning.mutation.graphql';
import configureContainerScanningMutation from './graphql/configure_container_scanning.mutation.graphql';

export { FEATURE_DISABLED_TOOLTIP } from '~/security_configuration/constants';

export const SMALL = 'SMALL';
export const MEDIUM = 'MEDIUM';
export const LARGE = 'LARGE';

// The backend will supply sizes matching the keys of this map; the values
// correspond to values acceptable to the underlying components' size props.
export const SCHEMA_TO_PROP_SIZE_MAP = {
  [SMALL]: 'xs',
  [MEDIUM]: 'md',
  [LARGE]: 'xl',
};

export const CUSTOM_VALUE_MESSAGE = s__(
  "SecurityConfiguration|Using custom settings. You won't receive automatic updates on this variable. %{anchorStart}Restore to default%{anchorEnd}",
);

export const featureToMutationMap = {
  ...featureToMutationMapCE,
  [REPORT_TYPE_DEPENDENCY_SCANNING]: {
    mutationId: 'configureDependencyScanning',
    getMutationPayload: (projectPath) => ({
      mutation: configureDependencyScanningMutation,
      variables: {
        input: {
          projectPath,
        },
      },
    }),
  },
  [REPORT_TYPE_CONTAINER_SCANNING]: {
    mutationId: 'configureContainerScanning',
    getMutationPayload: (projectPath) => ({
      mutation: configureContainerScanningMutation,
      variables: {
        input: {
          projectPath,
        },
      },
    }),
  },
};

export const CONFIGURATION_SNIPPET_MODAL_ID = 'CONFIGURATION_SNIPPET_MODAL_ID';

export const ANALYZER_STATUSES_NOT_CONFIGURED = 'not_configured';
export const ANALYZER_STATUSES_SUCCESS = 'success';
export const ANALYZER_STATUSES_FAILED = 'failed';
export const ANALYZER_STATUSES_STALE = 'stale';

export const GROUP_STATUS_ENABLED = 'enabled';
export const GROUP_STATUS_NOT_ENABLED = 'not_enabled';
export const GROUP_STATUS_PENDING = 'pending';
export const GROUP_STATUS_WARNING = 'warning';
export const GROUP_STATUS_STALE = 'stale';
export const GROUP_STATUS_FAILED = 'failed';

export const GROUP_STATUSES_LABELS = {
  [GROUP_STATUS_ENABLED]: s__('SecurityConfiguration|Enabled'),
  [GROUP_STATUS_NOT_ENABLED]: s__('SecurityConfiguration|Not enabled'),
  [GROUP_STATUS_PENDING]: s__('SecurityConfiguration|Pending'),
  [GROUP_STATUS_WARNING]: s__('SecurityConfiguration|Warning'),
  [GROUP_STATUS_FAILED]: s__('SecurityConfiguration|Failed'),
  [GROUP_STATUS_STALE]: s__('SecurityConfiguration|Stale'),
};

export const STATUS_NORMALIZATION_MAP = {
  [SCAN_PROFILE_SCANNER_HEALTH_ACTIVE]: GROUP_STATUS_ENABLED,
  [ANALYZER_STATUSES_SUCCESS]: GROUP_STATUS_ENABLED,
  [SCAN_PROFILE_SCANNER_HEALTH_PENDING]: GROUP_STATUS_PENDING,
  [SCAN_PROFILE_SCANNER_HEALTH_UNCONFIGURED]: GROUP_STATUS_NOT_ENABLED,
  [ANALYZER_STATUSES_NOT_CONFIGURED]: GROUP_STATUS_NOT_ENABLED,
  [ANALYZER_STATUSES_FAILED]: GROUP_STATUS_FAILED,
  [SCAN_PROFILE_SCANNER_HEALTH_FAILED]: GROUP_STATUS_FAILED,
  [ANALYZER_STATUSES_STALE]: GROUP_STATUS_STALE,
  [SCAN_PROFILE_SCANNER_HEALTH_STALE]: GROUP_STATUS_STALE,
  [SCAN_PROFILE_SCANNER_HEALTH_WARNING]: GROUP_STATUS_WARNING,
};

export const SCANNER_STATUS_ICONS = {
  [SCAN_PROFILE_SCANNER_HEALTH_PENDING]: 'status-waiting',
  [SCAN_PROFILE_SCANNER_HEALTH_UNCONFIGURED]: 'clear',
  [GROUP_STATUS_NOT_ENABLED]: 'clear',
  [SCAN_PROFILE_SCANNER_HEALTH_ACTIVE]: 'status-success',
  [GROUP_STATUS_ENABLED]: 'status-success',
  [SCAN_PROFILE_SCANNER_HEALTH_WARNING]: 'status_warning',
  [SCAN_PROFILE_SCANNER_HEALTH_FAILED]: 'status-failed',
  [SCAN_PROFILE_SCANNER_HEALTH_STALE]: 'status-scheduled',
};

export const SCANNER_STATUS_ICON_CLASSES = {
  [SCAN_PROFILE_SCANNER_HEALTH_PENDING]: 'gl-text-subtle',
  [SCAN_PROFILE_SCANNER_HEALTH_UNCONFIGURED]: 'gl-text-subtle',
  [GROUP_STATUS_NOT_ENABLED]: 'gl-text-subtle',
  [SCAN_PROFILE_SCANNER_HEALTH_ACTIVE]: 'gl-text-success',
  [GROUP_STATUS_ENABLED]: 'gl-text-success',
  [SCAN_PROFILE_SCANNER_HEALTH_WARNING]: 'gl-text-warning',
  [SCAN_PROFILE_SCANNER_HEALTH_FAILED]: 'gl-text-danger',
  [SCAN_PROFILE_SCANNER_HEALTH_STALE]: 'gl-text-subtle',
};

// Values of the ScanProfileTriggerType GraphQL enum.
export const SAST_FALSE_POSITIVE = 'SAST_FALSE_POSITIVE';
export const SAST_VULNERABILITY_RESOLUTION = 'SAST_VULNERABILITY_RESOLUTION';
export const SBOM_INGESTED = 'SBOM_INGESTED';
export const SECRET_DETECTION_FALSE_POSITIVE = 'SECRET_DETECTION_FALSE_POSITIVE';

export const TRIAGE_PRESET_CAPABILITY_GROUPS = [
  {
    title: s__('ScanProfiles|SAST'),
    capabilities: [
      {
        triggerType: SAST_FALSE_POSITIVE,
        icon: 'false-positive',
        title: s__('ScanProfiles|SAST false positive detection'),
      },
      {
        triggerType: SAST_VULNERABILITY_RESOLUTION,
        icon: 'merge-request',
        title: s__('ScanProfiles|SAST vulnerability resolution'),
      },
    ],
  },
  {
    title: s__('ScanProfiles|Dependencies'),
    capabilities: [
      {
        triggerType: SBOM_INGESTED,
        icon: 'package',
        title: s__('ScanProfiles|Dependency scanning auto-remediation'),
      },
    ],
  },
  {
    title: s__('ScanProfiles|Secrets'),
    capabilities: [
      {
        triggerType: SECRET_DETECTION_FALSE_POSITIVE,
        icon: 'key',
        title: s__('ScanProfiles|Secret detection false positive detection'),
      },
    ],
  },
];

export const TRIAGE_PRESET_CAPABILITIES = TRIAGE_PRESET_CAPABILITY_GROUPS.flatMap(
  ({ capabilities }) => capabilities,
);

export const TRIAGE_CAPABILITY_MARKERS = {
  [SAST_FALSE_POSITIVE]: { ai: true },
  [SAST_VULNERABILITY_RESOLUTION]: { ai: true },
  [SBOM_INGESTED]: { beta: true },
  [SECRET_DETECTION_FALSE_POSITIVE]: { ai: true },
};

export const FLOW_STATUS_UNAVAILABLE = 'FLOW_UNAVAILABLE';
export const FLOW_STATUSES_OFF_FOR_GROUP = ['FLOW_NOT_ENABLED', 'FOUNDATIONAL_FLOWS_DISABLED'];
export const FLOW_STATUSES_READY = ['AVAILABLE', 'NOT_APPLICABLE'];

export const TRIAGE_CAPABILITY_STATUS_OFF_FOR_GROUP = {
  label: s__('SecurityConfiguration|Off for group'),
  icon: 'status-alert',
  variant: 'warning',
};
export const TRIAGE_CAPABILITY_STATUS_UNAVAILABLE = {
  label: s__('SecurityConfiguration|Unavailable'),
  icon: 'status-failed',
  variant: 'danger',
};
export const TRIAGE_CAPABILITY_STATUS_ACTIVE = {
  label: s__('SecurityConfiguration|Active'),
  icon: 'status-success',
  variant: 'success',
};
export const TRIAGE_CAPABILITY_STATUS_OFF = {
  label: s__('SecurityConfiguration|Off'),
  icon: 'clear',
  variant: 'subtle',
};

export const TRIAGE_RUN_MODE_MANUAL = 'MANUAL';

export const TRIAGE_RUN_MODE_LABELS = {
  AUTO: s__('SecurityConfiguration|Automatic'),
  [TRIAGE_RUN_MODE_MANUAL]: s__('SecurityConfiguration|On demand'),
};

export const TRIAGE_SEVERITY_SCOPES = {
  CRITICAL: s__('ScanProfiles|Critical only'),
  HIGH: s__('ScanProfiles|High and above'),
  MEDIUM: s__('ScanProfiles|Medium and above'),
  LOW: s__('ScanProfiles|Low and above'),
  UNKNOWN: s__('ScanProfiles|Unknown and above'),
  INFO: s__('ScanProfiles|All severities'),
};

// The dependency auto-remediation scheduler has no info or unknown level.
export const TRIAGE_DEPENDENCY_SEVERITY_SCOPES = {
  ...TRIAGE_SEVERITY_SCOPES,
  UNKNOWN: TRIAGE_SEVERITY_SCOPES.LOW,
  INFO: TRIAGE_SEVERITY_SCOPES.LOW,
};

export const TRIAGE_UPGRADE_POLICIES = {
  PATCH: s__('ScanProfiles|Patch versions'),
  MINOR: s__('ScanProfiles|Minor and patch versions'),
  MAJOR: s__('ScanProfiles|Major, minor and patch versions'),
};
