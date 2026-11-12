import { s__ } from '~/locale';
import SecurityConfigurationTabs from './components/group_configuration_tabs.vue';
import ScannerDetails from './components/scan_profiles/scanner_details.vue';
import EnableScanners from './components/enable_scanners_wizard/app.vue';
import EnableScannersSelectApproach from './components/enable_scanners_wizard/select_approach.vue';
import EnableScannersSelectItems from './components/enable_scanners_wizard/select_items.vue';
import EnableScannersSelectScanners from './components/enable_scanners_wizard/select_scanners.vue';
import TriageWizardSelectProfile from './components/enable_scanners_wizard/select_profile.vue';
import EnableScannersSelectMode from './components/enable_scanners_wizard/select_mode.vue';
import TriageWizardReviewCapabilities from './components/enable_scanners_wizard/review_capabilities.vue';
import EnableScannersReview from './components/enable_scanners_wizard/review.vue';
import EnableScannersConfirmation from './components/enable_scanners_wizard/confirmation.vue';
import { scannerWizard } from './components/enable_scanners_wizard/scanner_wizard';
import {
  triageWizard,
  triageWizardConfirmation,
} from './components/enable_scanners_wizard/triage_wizard';
import {
  ROUTE_ENABLE_SCANNERS,
  ROUTE_APPROACH,
  ROUTE_ITEMS,
  ROUTE_SCANNERS,
  ROUTE_MODE,
  ROUTE_REVIEW,
  ROUTE_CONFIRMATION,
  ROUTE_ENABLE_TRIAGE_AND_REMEDIATION,
  ROUTE_TRIAGE_APPROACH,
  ROUTE_TRIAGE_ITEMS,
  ROUTE_TRIAGE_PROFILE,
  ROUTE_TRIAGE_MODE,
  ROUTE_TRIAGE_CAPABILITIES,
  ROUTE_TRIAGE_REVIEW,
  ROUTE_TRIAGE_CONFIRMATION,
} from './components/enable_scanners_wizard/constants';

const triageAndRemediationWizardRoute = {
  path: '/enable_triage_and_remediation',
  component: EnableScanners,
  props: triageWizard,
  meta: { breadcrumb: s__('SecurityConfiguration|Roll out Automated Triage and Remediation') },
  children: [
    {
      path: '',
      name: ROUTE_ENABLE_TRIAGE_AND_REMEDIATION,
      redirect: { name: ROUTE_TRIAGE_APPROACH },
    },
    { path: 'approach', name: ROUTE_TRIAGE_APPROACH, component: EnableScannersSelectApproach },
    { path: 'items', name: ROUTE_TRIAGE_ITEMS, component: EnableScannersSelectItems },
    { path: 'profile', name: ROUTE_TRIAGE_PROFILE, component: TriageWizardSelectProfile },
    { path: 'mode', name: ROUTE_TRIAGE_MODE, component: EnableScannersSelectMode },
    {
      path: 'capabilities',
      name: ROUTE_TRIAGE_CAPABILITIES,
      component: TriageWizardReviewCapabilities,
    },
    { path: 'review', name: ROUTE_TRIAGE_REVIEW, component: EnableScannersReview },
    {
      path: 'confirm',
      name: ROUTE_TRIAGE_CONFIRMATION,
      component: EnableScannersConfirmation,
      props: triageWizardConfirmation,
    },
  ],
};

export const createRoutes = () => [
  {
    path: '/',
    name: 'security_configuration',
    component: SecurityConfigurationTabs,
  },
  {
    path: '/scanners/:scanner_key',
    name: 'scanner_details',
    component: ScannerDetails,
  },
  {
    path: '/enable_scanners',
    component: EnableScanners,
    props: scannerWizard,
    children: [
      { path: '', name: ROUTE_ENABLE_SCANNERS, redirect: { name: ROUTE_APPROACH } },
      { path: 'approach', name: ROUTE_APPROACH, component: EnableScannersSelectApproach },
      { path: 'items', name: ROUTE_ITEMS, component: EnableScannersSelectItems },
      { path: 'scanners', name: ROUTE_SCANNERS, component: EnableScannersSelectScanners },
      { path: 'mode', name: ROUTE_MODE, component: EnableScannersSelectMode },
      { path: 'review', name: ROUTE_REVIEW, component: EnableScannersReview },
      { path: 'confirm', name: ROUTE_CONFIRMATION, component: EnableScannersConfirmation },
    ],
  },
  ...(gon.features?.triageAndRemediationProfilesUi ? [triageAndRemediationWizardRoute] : []),
  { path: '*', redirect: { name: 'security_configuration' } },
];
