import { __, s__ } from '~/locale';
import {
  SCAN_PROFILE_TYPE_SECRET_DETECTION,
  SCAN_PROFILE_TYPE_SAST,
  SCAN_PROFILE_TYPE_DEPENDENCY_SCANNING,
  SCAN_PROFILE_TYPE_BUSINESS_LOGIC,
} from '~/security_configuration/constants';
import {
  ROUTE_APPROACH,
  ROUTE_ITEMS,
  ROUTE_SCANNERS,
  ROUTE_MODE,
  ROUTE_REVIEW,
  ROUTE_CONFIRMATION,
  APPROACH_QUICK,
  ROUTE_TO_STEP_LABEL,
  ATTACH_MODE_OPTIONS,
  EVENT_VIEW_STEP,
  EVENT_START_WIZARD,
  EVENT_SELECT_SCANNER,
  EVENT_DESELECT_SCANNER,
  EVENT_SELECT_ITEM,
  EVENT_DESELECT_ITEM,
  EVENT_APPLY_WIZARD,
  EVENT_ABANDON_WIZARD,
} from './constants';

export const scannerWizard = {
  buildSteps: (wizard) => {
    const hasModeStep =
      gon.features?.scannerWizardAttachModes && wizard.approach === APPROACH_QUICK;

    return [
      { route: ROUTE_APPROACH, label: s__('SecurityConfiguration|Select approach') },
      {
        route: ROUTE_ITEMS,
        label: s__('SecurityConfiguration|Select projects'),
        count: wizard.areAllItemsSelected ? __('All') : wizard.selectedItems.length,
      },
      {
        route: ROUTE_SCANNERS,
        label: s__('SecurityConfiguration|Select scanners'),
        count: wizard.selectedProfiles.length,
        // Quick setup reaches this step only from the mode step.
        ...(hasModeStep && { previousRoute: ROUTE_MODE }),
      },
      hasModeStep && {
        route: ROUTE_MODE,
        label: s__('SecurityConfiguration|Select mode'),
        count: ATTACH_MODE_OPTIONS.find(({ value }) => value === wizard.attachMode)?.shortLabel,
      },
      { route: ROUTE_REVIEW, label: s__('SecurityConfiguration|Review configuration') },
    ].filter(Boolean);
  },
  // SkillGuard is configured from the security configuration page only while it is an
  // experiment, so the wizard skips it without hiding it from the pages that offer it.
  profileTypes: [
    SCAN_PROFILE_TYPE_SECRET_DETECTION,
    SCAN_PROFILE_TYPE_SAST,
    SCAN_PROFILE_TYPE_DEPENDENCY_SCANNING,
    SCAN_PROFILE_TYPE_BUSINESS_LOGIC,
  ],
  trackingEvents: {
    viewStep: EVENT_VIEW_STEP,
    startWizard: EVENT_START_WIZARD,
    selectScanner: EVENT_SELECT_SCANNER,
    deselectScanner: EVENT_DESELECT_SCANNER,
    selectItem: EVENT_SELECT_ITEM,
    deselectItem: EVENT_DESELECT_ITEM,
    applyWizard: EVENT_APPLY_WIZARD,
    abandonWizard: EVENT_ABANDON_WIZARD,
  },
  routes: {
    approach: ROUTE_APPROACH,
    items: ROUTE_ITEMS,
    profiles: ROUTE_SCANNERS,
    mode: ROUTE_MODE,
    review: ROUTE_REVIEW,
    confirmation: ROUTE_CONFIRMATION,
  },
  stepLabels: ROUTE_TO_STEP_LABEL,
  attachModeOptions: ATTACH_MODE_OPTIONS,
};
