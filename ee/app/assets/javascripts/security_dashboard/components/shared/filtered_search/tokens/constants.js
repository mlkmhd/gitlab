import { __, s__ } from '~/locale';
import { VULNERABILITY_STATE_OBJECTS } from 'ee/vulnerabilities/constants';
import {
  REPORT_TYPES_WITH_MANUALLY_ADDED,
  REPORT_TYPES_WITH_CLUSTER_IMAGE,
  REPORT_TYPES_CONTAINER_SCANNING_FOR_REGISTRY,
} from 'ee/security_dashboard/constants';
import { OPERATORS_OR, OPERATORS_IS } from '~/vue_shared/components/filtered_search_bar/constants';
import StatusToken from './status_token.vue';
import ActivityToken from './activity_token.vue';
import SeverityToken from './severity_token.vue';
import ImageToken from './image_token.vue';
import ClusterToken from './cluster_token.vue';
import ProjectToken from './project_token.vue';
import ScannerToken from './scanner_token.vue';
import IdentifierToken from './identifier_token.vue';
import ReportTypeToken from './report_type_token.vue';
import ReachabilityToken from './reachability_token.vue';
import ValidityCheckToken from './validity_check_token.vue';
import TrackedRefToken from './tracked_ref_token.vue';
import MalwareToken from './malware_token.vue';

export const STATUS_TOKEN_DEFINITION = {
  type: 'state',
  title: s__('SecurityReports|Status'),
  multiSelect: true,
  unique: true,
  token: StatusToken,
  operators: OPERATORS_OR,
};

export const PIPELINE_STATUS_TOKEN_DEFINITION = {
  ...STATUS_TOKEN_DEFINITION,
  hideDismissalReasons: true,
  defaultValue: [VULNERABILITY_STATE_OBJECTS.detected.searchParamValue],
};

export const SEVERITY_TOKEN_DEFINITION = {
  type: 'severity',
  title: s__('SecurityReports|Severity'),
  multiSelect: true,
  unique: true,
  token: SeverityToken,
  operators: OPERATORS_OR,
};

export const ACTIVITY_TOKEN_DEFINITION = {
  type: 'activity',
  title: s__('SecurityReports|Activity'),
  multiSelect: true,
  unique: true,
  token: ActivityToken,
  operators: OPERATORS_OR,
};

export const SCANNER_TOKEN_DEFINITION = {
  type: 'scanner',
  title: s__('SecurityReports|Scanner'),
  multiSelect: true,
  unique: true,
  token: ScannerToken,
  operators: OPERATORS_OR,
};

export const PROJECT_TOKEN_DEFINITION = {
  type: 'projectId',
  title: __('Project'),
  multiSelect: true,
  unique: true,
  token: ProjectToken,
  operators: OPERATORS_OR,
};

export const IMAGE_TOKEN_DEFINITION = {
  type: 'image',
  title: s__('SecurityReports|Image'),
  multiSelect: true,
  unique: true,
  token: ImageToken,
  operators: OPERATORS_OR,
};

export const CLUSTER_TOKEN_DEFINITION = {
  type: 'cluster',
  title: s__('SecurityReports|Cluster'),
  multiSelect: true,
  unique: true,
  token: ClusterToken,
  operators: OPERATORS_OR,
};

export const IDENTIFIER_TOKEN_DEFINITION = {
  type: 'identifier',
  title: s__('SecurityReports|Identifier'),
  multiSelect: false,
  unique: true,
  token: IdentifierToken,
  operators: OPERATORS_IS,
};

export const REPORT_TYPE_TOKEN_DEFINITION = {
  type: 'reportType',
  title: s__('SecurityReports|Report type'),
  multiSelect: true,
  unique: true,
  token: ReportTypeToken,
  operators: OPERATORS_OR,
};

export const REPORT_TYPE_PIPELINE_TOKEN_DEFINITION = {
  ...REPORT_TYPE_TOKEN_DEFINITION,
  reportTypes: {
    ...REPORT_TYPES_WITH_CLUSTER_IMAGE,
  },
};

export const REPORT_TYPE_DASHBOARD_TOKEN_DEFINITION = {
  ...REPORT_TYPE_TOKEN_DEFINITION,
  reportTypes: {
    ...REPORT_TYPES_WITH_MANUALLY_ADDED,
    ...REPORT_TYPES_WITH_CLUSTER_IMAGE,
    ...REPORT_TYPES_CONTAINER_SCANNING_FOR_REGISTRY,
  },
};

export const REACHABILITY_TOKEN_DEFINITION = {
  type: 'reachability',
  title: s__('SecurityReports|Reachability'),
  multiSelect: false,
  unique: true,
  token: ReachabilityToken,
  operators: OPERATORS_IS,
};

export const VALIDITY_CHECK_TOKEN_DEFINITION = {
  type: 'validityCheck',
  title: s__('SecurityReports|Validity check'),
  multiSelect: false,
  unique: true,
  token: ValidityCheckToken,
  operators: OPERATORS_IS,
};

export const TRACKED_REF_TOKEN_DEFINITION = {
  type: 'trackedRefIds',
  title: s__('SecurityReports|Tracked ref'),
  multiSelect: true,
  unique: true,
  token: TrackedRefToken,
  operators: OPERATORS_OR,
};

export const SINGLE_SELECT_TRACKED_REF_TOKEN_DEFINITION = {
  ...TRACKED_REF_TOKEN_DEFINITION,
  multiSelect: false,
  operators: OPERATORS_IS,
};

export const MALWARE_TOKEN_DEFINITION = {
  type: 'malware',
  title: s__('SecurityReports|Malware'),
  multiSelect: false,
  unique: true,
  token: MalwareToken,
  operators: OPERATORS_IS,
};
