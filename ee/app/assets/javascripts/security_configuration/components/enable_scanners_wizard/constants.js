import { s__ } from '~/locale';

export const ROUTE_ENABLE_SCANNERS = 'enable_scanners';
export const ROUTE_APPROACH = 'enable_step_approach';
export const ROUTE_ITEMS = 'enable_step_items';
export const ROUTE_SCANNERS = 'enable_step_scanners';
export const ROUTE_MODE = 'enable_step_mode';
export const ROUTE_REVIEW = 'enable_step_review';
export const ROUTE_CONFIRMATION = 'enable_confirmation';

export const ROUTE_ENABLE_TRIAGE_AND_REMEDIATION = 'enable_triage_and_remediation';
export const ROUTE_TRIAGE_APPROACH = 'triage_step_approach';
export const ROUTE_TRIAGE_ITEMS = 'triage_step_items';
export const ROUTE_TRIAGE_PROFILE = 'triage_step_profile';
export const ROUTE_TRIAGE_MODE = 'triage_step_mode';
export const ROUTE_TRIAGE_CAPABILITIES = 'triage_step_capabilities';
export const ROUTE_TRIAGE_REVIEW = 'triage_step_review';
export const ROUTE_TRIAGE_CONFIRMATION = 'triage_confirmation';

export const APPROACH_QUICK = 'quick';
export const APPROACH_ADVANCED = 'advanced';

export const ATTACH_MODE_SET = 'SET';
export const ATTACH_MODE_FILL_SCAN_GAPS = 'FILL_SCAN_GAPS';
export const ATTACH_MODE_REPLACE = 'REPLACE';
export const ATTACH_MODE_FILL_PROFILE_GAPS = 'FILL_PROFILE_GAPS';

export const ATTACH_MODE_OPTIONS = [
  {
    value: ATTACH_MODE_SET,
    label: s__('SecurityConfiguration|All projects'),
    shortLabel: s__('SecurityConfiguration|All'),
    help: s__(
      'SecurityConfiguration|Adds the scan profiles to every project and replaces existing scan profiles for that scanner. Projects that scan another way, such as CI/CD configuration, a policy, or another tool, run both scans.',
    ),
    selectedMessage: s__('SecurityConfiguration|All projects are selected.'),
    rolloutMessage: s__(
      'SecurityConfiguration|Your configuration has been applied and is rolling out to projects in batches. Profiles will be applied to %{strongStart}all projects%{strongEnd} as each batch completes — this may take a few minutes.',
    ),
  },
  {
    value: ATTACH_MODE_FILL_SCAN_GAPS,
    label: s__("SecurityConfiguration|Projects that don't scan yet"),
    shortLabel: s__("SecurityConfiguration|Don't scan yet"),
    help: s__(
      'SecurityConfiguration|Adds the scan profiles to projects with no scan for that scanner. Projects that already scan keep their current setup.',
    ),
    selectedMessage: s__("SecurityConfiguration|Projects that don't scan yet are selected."),
    rolloutMessage: s__(
      "SecurityConfiguration|Your configuration has been applied and is rolling out to projects in batches. Profiles will be applied to %{strongStart}projects that don't scan yet%{strongEnd} as each batch completes — this may take a few minutes.",
    ),
    recommended: true,
  },
  {
    value: ATTACH_MODE_REPLACE,
    label: s__('SecurityConfiguration|Replace existing'),
    shortLabel: s__('SecurityConfiguration|Replace existing'),
    help: s__(
      'SecurityConfiguration|For projects that already have a scan profile for that scanner, removes it and adds the new scan profile.',
    ),
    selectedMessage: s__('SecurityConfiguration|Projects with an existing profile are selected.'),
    rolloutMessage: s__(
      'SecurityConfiguration|Your configuration has been applied and is rolling out to projects in batches. Profiles will be applied to %{strongStart}projects that already have a profile%{strongEnd}, replacing it as each batch completes — this may take a few minutes.',
    ),
  },
];

export const TRIAGE_ATTACH_MODE_OPTIONS = [
  {
    value: ATTACH_MODE_SET,
    label: s__('SecurityConfiguration|All projects'),
    shortLabel: s__('SecurityConfiguration|All'),
    help: s__(
      'SecurityConfiguration|Adds the profile to every project, including projects that turned Automated Triage and Remediation off, and replaces any Automated Triage and Remediation profile they already have.',
    ),
    selectedMessage: s__('SecurityConfiguration|All projects are selected.'),
    rolloutMessage: s__(
      'SecurityConfiguration|%{strongStart}%{profileName}%{strongEnd} is rolling out to all projects in batches. This may take a few minutes.',
    ),
  },
  {
    value: ATTACH_MODE_FILL_PROFILE_GAPS,
    label: s__('SecurityConfiguration|Fill gaps'),
    shortLabel: s__('SecurityConfiguration|Fill gaps'),
    help: s__(
      'SecurityConfiguration|Adds the profile to projects without an Automated Triage and Remediation profile of their own. Projects with their own profile keep it.',
    ),
    selectedMessage: s__(
      'SecurityConfiguration|Projects without an Automated Triage and Remediation profile of their own are selected.',
    ),
    rolloutMessage: s__(
      'SecurityConfiguration|%{strongStart}%{profileName}%{strongEnd} is rolling out in batches to projects without an Automated Triage and Remediation profile of their own. This may take a few minutes.',
    ),
    recommended: true,
  },
  {
    value: ATTACH_MODE_REPLACE,
    label: s__('SecurityConfiguration|Replace existing profiles'),
    shortLabel: s__('SecurityConfiguration|Replace existing'),
    help: s__(
      'SecurityConfiguration|For projects that already have their own Automated Triage and Remediation profile, replaces it with this one. Other projects stay as they are.',
    ),
    selectedMessage: s__(
      'SecurityConfiguration|Projects with an Automated Triage and Remediation profile of their own are selected.',
    ),
    rolloutMessage: s__(
      'SecurityConfiguration|%{strongStart}%{profileName}%{strongEnd} is rolling out in batches to projects with an Automated Triage and Remediation profile of their own, replacing it. This may take a few minutes.',
    ),
  },
];

export const EVENT_VIEW_STEP = 'view_enable_scanners_wizard_step';
export const EVENT_START_WIZARD = 'start_enable_scanners_wizard';
export const EVENT_SELECT_SCANNER = 'select_enable_scanners_wizard_scanner';
export const EVENT_DESELECT_SCANNER = 'deselect_enable_scanners_wizard_scanner';
export const EVENT_SELECT_ITEM = 'select_enable_scanners_wizard_item';
export const EVENT_DESELECT_ITEM = 'deselect_enable_scanners_wizard_item';
export const EVENT_APPLY_WIZARD = 'apply_enable_scanners_wizard';
export const EVENT_ABANDON_WIZARD = 'abandon_enable_scanners_wizard';

export const EVENT_TRIAGE_VIEW_STEP = 'view_triage_and_remediation_wizard_step';
export const EVENT_TRIAGE_START_WIZARD = 'start_triage_and_remediation_wizard';
export const EVENT_TRIAGE_APPLY_WIZARD = 'apply_triage_and_remediation_wizard';
export const EVENT_TRIAGE_ABANDON_WIZARD = 'abandon_triage_and_remediation_wizard';

export const STEP_LABEL_APPROACH = 'approach';
export const STEP_LABEL_ITEMS = 'items';
export const STEP_LABEL_SCANNERS = 'scanners';
export const STEP_LABEL_PROFILE = 'profile';
export const STEP_LABEL_MODE = 'mode';
export const STEP_LABEL_CAPABILITIES = 'capabilities';
export const STEP_LABEL_REVIEW = 'review';
export const STEP_LABEL_CONFIRMATION = 'confirmation';

export const ROUTE_TO_STEP_LABEL = {
  [ROUTE_APPROACH]: STEP_LABEL_APPROACH,
  [ROUTE_ITEMS]: STEP_LABEL_ITEMS,
  [ROUTE_SCANNERS]: STEP_LABEL_SCANNERS,
  [ROUTE_MODE]: STEP_LABEL_MODE,
  [ROUTE_REVIEW]: STEP_LABEL_REVIEW,
  [ROUTE_CONFIRMATION]: STEP_LABEL_CONFIRMATION,
};

export const TRIAGE_ROUTE_TO_STEP_LABEL = {
  [ROUTE_TRIAGE_APPROACH]: STEP_LABEL_APPROACH,
  [ROUTE_TRIAGE_ITEMS]: STEP_LABEL_ITEMS,
  [ROUTE_TRIAGE_PROFILE]: STEP_LABEL_PROFILE,
  [ROUTE_TRIAGE_MODE]: STEP_LABEL_MODE,
  [ROUTE_TRIAGE_CAPABILITIES]: STEP_LABEL_CAPABILITIES,
  [ROUTE_TRIAGE_REVIEW]: STEP_LABEL_REVIEW,
  [ROUTE_TRIAGE_CONFIRMATION]: STEP_LABEL_CONFIRMATION,
};
