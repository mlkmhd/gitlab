import Vue from 'vue';
import VueRouter from 'vue-router';
import VueApollo from 'vue-apollo';
import { GlLink } from '@gitlab/ui';
import { shallowMountExtended } from 'helpers/vue_test_utils_helper';
import createMockApollo from 'helpers/mock_apollo_helper';
import waitForPromises from 'helpers/wait_for_promises';
import EnableScannersWizard from 'ee/security_configuration/components/enable_scanners_wizard/app.vue';
import { createRoutes } from 'ee/security_configuration/routes';
import {
  triageWizard,
  triageWizardConfirmation,
} from 'ee/security_configuration/components/enable_scanners_wizard/triage_wizard';
import {
  ROUTE_TRIAGE_APPROACH,
  ROUTE_TRIAGE_ITEMS,
  ROUTE_TRIAGE_PROFILE,
  ROUTE_TRIAGE_MODE,
  ROUTE_TRIAGE_CAPABILITIES,
  ROUTE_TRIAGE_REVIEW,
  ROUTE_TRIAGE_CONFIRMATION,
  APPROACH_QUICK,
  APPROACH_ADVANCED,
} from 'ee/security_configuration/components/enable_scanners_wizard/constants';
import ProfileCard from 'ee/security_configuration/components/enable_scanners_wizard/profile_card.vue';
import CapabilitiesCell from 'ee/security_inventory/components/capabilities_cell.vue';
import ReviewCapabilities from 'ee/security_configuration/components/enable_scanners_wizard/review_capabilities.vue';
import groupAvailableSecurityScanProfilesQuery from 'ee/security_configuration/graphql/scan_profiles/group_available_security_scan_profiles.query.graphql';
import securityScanProfileAttachMutation from 'ee/security_configuration/graphql/scan_profiles/security_scan_profile_attach.mutation.graphql';
import { mockGroupUserPermissions, mockScanner } from '../scan_profiles/mock_data';
import { triagePresets, standardPreset } from './mock_data';

Vue.use(VueRouter);
Vue.use(VueApollo);

describe('triageWizard', () => {
  let wrapper;
  let router;
  let attachHandler;

  const createRouter = ({ triageAndRemediationProfilesUi }) => {
    window.gon.features = { triageAndRemediationProfilesUi };
    return new VueRouter({ routes: createRoutes() });
  };

  const createWizard = async ({ approach = APPROACH_QUICK } = {}) => {
    router = createRouter({ triageAndRemediationProfilesUi: true });
    await router.push({ name: ROUTE_TRIAGE_APPROACH });
    attachHandler = jest.fn().mockResolvedValue({
      data: {
        securityScanProfileAttach: {
          __typename: 'SecurityScanProfileAttachPayload',
          clientMutationId: '1',
          errors: [],
        },
      },
    });

    wrapper = shallowMountExtended(EnableScannersWizard, {
      router,
      propsData: triageWizard,
      apolloProvider: createMockApollo([
        [
          groupAvailableSecurityScanProfilesQuery,
          jest.fn().mockResolvedValue({
            data: {
              group: {
                id: 'gid://gitlab/Group/1',
                name: 'group',
                userPermissions: mockGroupUserPermissions,
                availableSecurityScanProfiles: [mockScanner, ...triagePresets],
                __typename: 'Group',
              },
            },
          }),
        ],
        [securityScanProfileAttachMutation, attachHandler],
      ]),
      provide: { groupFullPath: 'group/path', groupId: 1 },
      data: () => ({ approach }),
    });
    await waitForPromises();
  };

  const clickNext = async () => {
    wrapper.findComponentByTestId('next-button').vm.$emit('click');
    await waitForPromises();
  };

  describe('route with triage_and_remediation_profiles_ui enabled', () => {
    it('renders the wizard on its approach step', async () => {
      router = createRouter({ triageAndRemediationProfilesUi: true });
      await router.push('/enable_triage_and_remediation');
      const { name, matched } = router.currentRoute;

      expect(name).toBe(ROUTE_TRIAGE_APPROACH);
      expect(matched[0].components.default.name).toBe(EnableScannersWizard.name);
      expect(matched[0].props.default.trackingEvents).toEqual(triageWizard.trackingEvents);
      expect(matched[0].meta.breadcrumb).toBe('Roll out Automated Triage and Remediation');
    });
  });

  describe('confirmation route', () => {
    it('pass the triage copy to the confirmation', async () => {
      router = createRouter({ triageAndRemediationProfilesUi: true });
      await router.push({ name: ROUTE_TRIAGE_CONFIRMATION });
      const { matched } = router.currentRoute;

      expect(matched[1].props.default).toEqual(triageWizardConfirmation);
      expect(triageWizardConfirmation.securityConfigurationTab).toBe(
        'automated-triage-and-remediation',
      );
      expect(triageWizardConfirmation.title).toBe(
        'Automated Triage and Remediation is rolling out',
      );
    });
  });

  it('pass the Profile card to the review step', () => {
    const steps = triageWizard.buildSteps({
      approach: APPROACH_ADVANCED,
      areAllItemsSelected: false,
      selectedItems: [],
      selectedProfiles: [],
    });

    expect(steps.find(({ route }) => route === ROUTE_TRIAGE_REVIEW).props).toEqual({
      profilesCard: ProfileCard,
    });
  });

  it('pass the Capabilities column to the projects step', () => {
    const steps = triageWizard.buildSteps({
      approach: APPROACH_ADVANCED,
      areAllItemsSelected: false,
      selectedItems: [],
      selectedProfiles: [],
    });

    expect(steps.find(({ route }) => route === ROUTE_TRIAGE_ITEMS).props).toEqual({
      coverageColumns: [
        {
          key: 'capabilities',
          label: 'Capabilities',
          component: CapabilitiesCell,
          props: { hideProfileActions: true },
        },
      ],
    });
  });

  describe('route with triage_and_remediation_profiles_ui disabled', () => {
    it('hide the triage route', () => {
      router = createRouter({ triageAndRemediationProfilesUi: false });

      expect(router.options.routes.map(({ path }) => path)).not.toContain(
        '/enable_triage_and_remediation',
      );
    });
  });

  it('return the preset step after projects', () => {
    const steps = triageWizard.buildSteps({
      approach: APPROACH_ADVANCED,
      areAllItemsSelected: false,
      selectedItems: [],
      selectedProfiles: [],
    });

    expect(steps.map(({ label }) => label)).toEqual([
      'Select approach',
      'Select projects',
      'Choose a profile',
      'Review capabilities',
      'Review configuration',
    ]);
  });

  it('pass its approach copy and exit modal title', () => {
    const [approachStep] = triageWizard.buildSteps({
      approach: APPROACH_QUICK,
      areAllItemsSelected: true,
      selectedItems: [],
      selectedProfiles: [],
    });

    expect(approachStep.props).toEqual({
      quickTitle: 'Apply one profile group-wide',
      quickDescription:
        'Pick one profile for the whole group. You review what it runs before anything applies.',
      advancedTitle: 'Choose projects and a profile',
      advancedDescription:
        'Pick exactly which projects get the profile you choose. Leaves the rest alone.',
      footnote: '',
    });
    expect(triageWizard.exitModalTitle).toBe('Exit setup?');
  });

  it('pass its own tracking events', () => {
    expect(triageWizard.trackingEvents).toEqual({
      viewStep: 'view_triage_and_remediation_wizard_step',
      startWizard: 'start_triage_and_remediation_wizard',
      applyWizard: 'apply_triage_and_remediation_wizard',
      abandonWizard: 'abandon_triage_and_remediation_wizard',
    });
  });

  it('hide scanner profiles', async () => {
    await createWizard();

    expect(wrapper.vm.availableScanners).toEqual(triagePresets);
  });

  it('pass SET, FILL_PROFILE_GAPS and REPLACE', () => {
    expect(triageWizard.attachModeOptions.map(({ value }) => value)).toEqual([
      'SET',
      'FILL_PROFILE_GAPS',
      'REPLACE',
    ]);
  });

  describe('quick setup', () => {
    const buildQuickSteps = () =>
      triageWizard.buildSteps({
        approach: APPROACH_QUICK,
        areAllItemsSelected: true,
        selectedItems: [],
        selectedProfiles: [],
        attachMode: 'FILL_PROFILE_GAPS',
      });

    it('apply Standard and show the mode step', async () => {
      await createWizard();

      await clickNext();

      expect(wrapper.vm.$route.name).toBe(ROUTE_TRIAGE_MODE);
      expect(wrapper.vm.selectedProfiles).toEqual([standardPreset]);
    });

    it('pass the Profile card to the mode step', () => {
      const modeStep = buildQuickSteps().find(({ route }) => route === ROUTE_TRIAGE_MODE);

      expect(modeStep.props).toEqual({ profilesCard: ProfileCard });
      expect(modeStep.count).toBe('Fill gaps');
    });

    it('show Review capabilities after the mode step', async () => {
      await createWizard();
      await clickNext();

      await clickNext();

      expect(wrapper.vm.$route.name).toBe(ROUTE_TRIAGE_CAPABILITIES);
      expect(wrapper.vm.$route.matched[1].components.default.name).toBe(ReviewCapabilities.name);
    });

    it('link every step but projects and profile', async () => {
      await createWizard();

      expect(wrapper.findAllComponents(GlLink).wrappers.map((link) => link.props('to'))).toEqual([
        { name: ROUTE_TRIAGE_APPROACH },
        { name: ROUTE_TRIAGE_MODE },
        { name: ROUTE_TRIAGE_CAPABILITIES },
        { name: ROUTE_TRIAGE_REVIEW },
      ]);
    });

    it('return to the mode step from Choose a profile', () => {
      const profileStep = buildQuickSteps().find(({ route }) => route === ROUTE_TRIAGE_PROFILE);

      expect(profileStep.previousRoute).toBe(ROUTE_TRIAGE_MODE);
    });

    it('submit FILL_PROFILE_GAPS by default', async () => {
      await createWizard();
      await clickNext();
      await router.push({ name: ROUTE_TRIAGE_REVIEW });

      await clickNext();

      expect(attachHandler).toHaveBeenCalledWith({
        input: expect.objectContaining({
          securityScanProfileId: standardPreset.id,
          mode: 'FILL_PROFILE_GAPS',
        }),
      });
    });
  });

  describe('advanced setup', () => {
    it('hide the mode step', () => {
      const steps = triageWizard.buildSteps({
        approach: APPROACH_ADVANCED,
        areAllItemsSelected: false,
        selectedItems: [],
        selectedProfiles: [],
      });

      expect(steps.map(({ route }) => route)).not.toContain(ROUTE_TRIAGE_MODE);
    });

    it('show Select projects next', async () => {
      await createWizard({ approach: APPROACH_ADVANCED });

      await clickNext();

      expect(wrapper.vm.$route.name).toBe(ROUTE_TRIAGE_ITEMS);
    });
  });
});
