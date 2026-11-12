import { __, s__ } from '~/locale';
import { SCAN_PROFILE_TYPE_TRIAGE_AND_REMEDIATION } from '~/security_configuration/constants';
import { CAPABILITIES_COLUMN } from 'ee/security_inventory/constants';
import CapabilitiesCell from 'ee/security_inventory/components/capabilities_cell.vue';
import {
  ROUTE_TRIAGE_APPROACH,
  ROUTE_TRIAGE_ITEMS,
  ROUTE_TRIAGE_PROFILE,
  ROUTE_TRIAGE_MODE,
  ROUTE_TRIAGE_CAPABILITIES,
  ROUTE_TRIAGE_REVIEW,
  ROUTE_TRIAGE_CONFIRMATION,
  TRIAGE_ROUTE_TO_STEP_LABEL,
  TRIAGE_ATTACH_MODE_OPTIONS,
  APPROACH_QUICK,
  EVENT_TRIAGE_VIEW_STEP,
  EVENT_TRIAGE_START_WIZARD,
  EVENT_TRIAGE_APPLY_WIZARD,
  EVENT_TRIAGE_ABANDON_WIZARD,
} from './constants';
import ProfileCard from './profile_card.vue';

export const triageWizard = {
  buildSteps: (wizard) => {
    const isQuick = wizard.approach === APPROACH_QUICK;

    return [
      {
        route: ROUTE_TRIAGE_APPROACH,
        label: s__('SecurityConfiguration|Select approach'),
        props: {
          quickTitle: s__('SecurityConfiguration|Apply one profile group-wide'),
          quickDescription: s__(
            'SecurityConfiguration|Pick one profile for the whole group. You review what it runs before anything applies.',
          ),
          advancedTitle: s__('SecurityConfiguration|Choose projects and a profile'),
          advancedDescription: s__(
            'SecurityConfiguration|Pick exactly which projects get the profile you choose. Leaves the rest alone.',
          ),
          footnote: '',
        },
      },
      {
        route: ROUTE_TRIAGE_ITEMS,
        label: s__('SecurityConfiguration|Select projects'),
        count: wizard.areAllItemsSelected ? __('All') : wizard.selectedItems.length,
        props: {
          coverageColumns: [
            {
              ...CAPABILITIES_COLUMN,
              component: CapabilitiesCell,
              props: { hideProfileActions: true },
            },
          ],
        },
      },
      {
        route: ROUTE_TRIAGE_PROFILE,
        label: s__('SecurityConfiguration|Choose a profile'),
        // Quick setup reaches this step only from the mode step's Profile card.
        ...(isQuick && { previousRoute: ROUTE_TRIAGE_MODE }),
      },
      isQuick && {
        route: ROUTE_TRIAGE_MODE,
        label: s__('SecurityConfiguration|Select mode'),
        count: TRIAGE_ATTACH_MODE_OPTIONS.find(({ value }) => value === wizard.attachMode)
          ?.shortLabel,
        props: { profilesCard: ProfileCard },
      },
      {
        route: ROUTE_TRIAGE_CAPABILITIES,
        label: s__('SecurityConfiguration|Review capabilities'),
      },
      {
        route: ROUTE_TRIAGE_REVIEW,
        label: s__('SecurityConfiguration|Review configuration'),
        props: { profilesCard: ProfileCard },
      },
    ].filter(Boolean);
  },
  profileTypes: [SCAN_PROFILE_TYPE_TRIAGE_AND_REMEDIATION],
  trackingEvents: {
    viewStep: EVENT_TRIAGE_VIEW_STEP,
    startWizard: EVENT_TRIAGE_START_WIZARD,
    applyWizard: EVENT_TRIAGE_APPLY_WIZARD,
    abandonWizard: EVENT_TRIAGE_ABANDON_WIZARD,
  },
  routes: {
    approach: ROUTE_TRIAGE_APPROACH,
    items: ROUTE_TRIAGE_ITEMS,
    profiles: ROUTE_TRIAGE_PROFILE,
    mode: ROUTE_TRIAGE_MODE,
    capabilities: ROUTE_TRIAGE_CAPABILITIES,
    review: ROUTE_TRIAGE_REVIEW,
    confirmation: ROUTE_TRIAGE_CONFIRMATION,
  },
  stepLabels: TRIAGE_ROUTE_TO_STEP_LABEL,
  attachModeOptions: TRIAGE_ATTACH_MODE_OPTIONS,
  exitModalTitle: s__('SecurityConfiguration|Exit setup?'),
};

export const triageWizardConfirmation = {
  securityConfigurationTab: 'automated-triage-and-remediation',
  title: s__('SecurityConfiguration|Automated Triage and Remediation is rolling out'),
  itemsRolloutMessage: s__(
    'SecurityConfiguration|%{strongStart}%{profileName}%{strongEnd} is rolling out to %{itemCount} in batches. This may take a few minutes.',
  ),
};
