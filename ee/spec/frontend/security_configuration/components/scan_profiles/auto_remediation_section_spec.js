import Vue, { nextTick } from 'vue';
import VueApollo from 'vue-apollo';
import { GlAlert } from '@gitlab/ui';
import { shallowMountExtended } from 'helpers/vue_test_utils_helper';
import { stubComponent } from 'helpers/stub_component';
import createMockApollo from 'helpers/mock_apollo_helper';
import waitForPromises from 'helpers/wait_for_promises';
import SectionLoader from '~/vue_shared/security_configuration/components/section_loader.vue';
import AutoRemediationSection from 'ee/security_configuration/components/scan_profiles/auto_remediation_section.vue';
import AutoRemediationCapabilities from 'ee/security_configuration/components/scan_profiles/auto_remediation_capabilities.vue';
import AutoRemediationCard from 'ee/security_configuration/components/scan_profiles/auto_remediation_card.vue';
import TriageProfileDrawer from 'ee/security_configuration/components/scan_profiles/triage_profile_drawer.vue';
import detachMutation from 'ee/security_configuration/graphql/scan_profiles/security_scan_profile_detach.mutation.graphql';
import projectProfilesQuery from 'ee/security_configuration/graphql/scan_profiles/project_security_scan_profiles.query.graphql';
import * as Sentry from '~/sentry/sentry_browser_wrapper';
import { confirmAction } from '~/lib/utils/confirm_via_gl_modal/confirm_action';
import { mockScanner, mockTriageAndRemediationProfile } from './mock_data';

jest.mock('~/sentry/sentry_browser_wrapper');
jest.mock('~/lib/utils/confirm_via_gl_modal/confirm_action');

Vue.use(VueApollo);

describe('AutoRemediationSection', () => {
  let wrapper;
  let queryHandler;
  let detachHandler;
  let showToast;
  let focusProfileLink;

  const buildResponse = (profiles = [], capabilities = []) => ({
    data: {
      project: {
        id: 'gid://gitlab/Project/1',
        name: 'project',
        securityScanProfiles: profiles,
        triageAndRemediationCoverage: { capabilities, __typename: 'TriageAndRemediationCoverage' },
        __typename: 'Project',
      },
    },
  });

  const createComponent = ({
    provide = {},
    glFeatures = { triageAndRemediationProfilesUi: true },
  } = {}) => {
    wrapper = shallowMountExtended(AutoRemediationSection, {
      apolloProvider: createMockApollo([
        [projectProfilesQuery, queryHandler],
        [detachMutation, detachHandler],
      ]),
      provide: {
        projectFullPath: 'group/project',
        canApplyProfiles: true,
        securityScanProfilesLicensed: true,
        glFeatures,
        ...provide,
      },
      stubs: {
        GlAlert: false,
        AutoRemediationCard: stubComponent(AutoRemediationCard, {
          methods: { focusProfileLink },
        }),
      },
      directives: { GlTooltip: {} },
      mocks: { $toast: { show: showToast } },
    });
    return waitForPromises();
  };

  const findCapabilities = () => wrapper.findComponent(AutoRemediationCapabilities);
  const findCard = () => wrapper.findComponent(AutoRemediationCard);
  const findLoader = () => wrapper.findComponent(SectionLoader);
  const findDrawers = () => wrapper.findAllComponents(TriageProfileDrawer).wrappers;
  const findDrawer = () => findDrawers().find((drawer) => !drawer.props('detailsOnly'));
  const findDetailsDrawer = () => findDrawers().find((drawer) => drawer.props('detailsOnly'));
  const findRemoveButton = () => wrapper.findComponentByTestId('auto-remediation-remove-button');
  const findRemoveError = () => wrapper.findByTestId('auto-remediation-remove-error');
  const findSection = () => wrapper.findByTestId('auto-remediation-section');
  const findChangeButton = () => wrapper.findComponentByTestId('auto-remediation-change-button');
  const findDescription = () => wrapper.findByTestId('auto-remediation-description');

  beforeEach(() => {
    queryHandler = jest.fn().mockResolvedValue(buildResponse());
    focusProfileLink = jest.fn();
    detachHandler = jest.fn().mockResolvedValue({
      data: {
        securityScanProfileDetach: {
          clientMutationId: null,
          errors: [],
          __typename: 'SecurityScanProfileDetachPayload',
        },
      },
    });
    confirmAction.mockResolvedValue(true);
    showToast = jest.fn();
  });

  describe('when the feature flag is disabled', () => {
    beforeEach(() => createComponent({ glFeatures: { triageAndRemediationProfilesUi: false } }));

    it('renders nothing and does not query', () => {
      expect(findSection().exists()).toBe(false);
      expect(queryHandler).not.toHaveBeenCalled();
    });
  });

  describe('when scan profiles are not licensed', () => {
    beforeEach(() => createComponent({ provide: { securityScanProfilesLicensed: false } }));

    it('renders nothing and does not query', () => {
      expect(findSection().exists()).toBe(false);
      expect(queryHandler).not.toHaveBeenCalled();
    });
  });

  describe('while the profiles are loading', () => {
    beforeEach(() => {
      createComponent();
    });

    it('shows a loader instead of the card and the heading', () => {
      expect(findLoader().exists()).toBe(true);
      expect(findCard().exists()).toBe(false);
      expect(wrapper.find('h2').exists()).toBe(false);
    });
  });

  describe('when no triage and remediation profile is attached', () => {
    beforeEach(() => {
      queryHandler.mockResolvedValue(buildResponse([mockScanner]));
      return createComponent();
    });

    it('queries the project by full path', () => {
      expect(queryHandler).toHaveBeenCalledWith({ fullPath: 'group/project' });
    });

    it('shows the card without a profile', () => {
      expect(findCard().props('profile')).toBeNull();
    });

    it('has no heading, no description and no change button', () => {
      expect(wrapper.find('h2').exists()).toBe(false);
      expect(findDescription().exists()).toBe(false);
      expect(findChangeButton().exists()).toBe(false);
    });
  });

  describe('when a triage and remediation profile is attached among others', () => {
    beforeEach(() => {
      queryHandler.mockResolvedValue(buildResponse([mockScanner, mockTriageAndRemediationProfile]));
      return createComponent();
    });

    it('passes the matching profile to the card', () => {
      expect(findCard().props()).toMatchObject({
        profile: expect.objectContaining({ id: mockTriageAndRemediationProfile.id }),
        canApplyProfiles: true,
      });
    });

    it('shows the heading', () => {
      expect(wrapper.find('h2').text()).toBe('Automated Triage and Remediation');
    });

    it('describes the section', () => {
      expect(findDescription().text()).toBe(
        'Define how GitLab triages and fixes vulnerabilities in this project.',
      );
    });

    it('shows the change profile button', () => {
      expect(findChangeButton().text()).toBe('Change profile');
    });
  });

  describe('when a profile is attached and the user cannot apply profiles', () => {
    beforeEach(() => {
      queryHandler.mockResolvedValue(buildResponse([mockTriageAndRemediationProfile]));
      return createComponent({ provide: { canApplyProfiles: false } });
    });

    it('hides the change profile button', () => {
      expect(findChangeButton().exists()).toBe(false);
    });
  });

  describe('the capabilities', () => {
    it('are not shown when no profile is attached', async () => {
      await createComponent();

      expect(findCapabilities().exists()).toBe(false);
    });

    it('are shown with the attached profile and the project coverage', async () => {
      const capabilities = [
        { triggerType: 'SBOM_INGESTED', enabled: true, runMode: 'AUTO', flowStatus: 'AVAILABLE' },
      ];
      queryHandler.mockResolvedValue(
        buildResponse([mockTriageAndRemediationProfile], capabilities),
      );
      await createComponent();

      expect(findCapabilities().props()).toMatchObject({
        profile: expect.objectContaining({ id: mockTriageAndRemediationProfile.id }),
        capabilities: [expect.objectContaining({ triggerType: 'SBOM_INGESTED' })],
      });
    });
  });

  describe('the profile drawer', () => {
    describe('when no profile is attached', () => {
      beforeEach(() => createComponent());

      it('is closed, with this project and no applied profile', () => {
        expect(findDrawer().props()).toMatchObject({
          open: false,
          presetId: '',
          project: expect.objectContaining({ id: 'gid://gitlab/Project/1' }),
        });
      });

      it('opens when the card asks to select a profile', async () => {
        findCard().vm.$emit('select-profile');
        await nextTick();

        expect(findDrawer().props('open')).toBe(true);
      });
    });

    describe('when a profile is attached', () => {
      beforeEach(() => {
        queryHandler
          .mockResolvedValueOnce(buildResponse([mockTriageAndRemediationProfile]))
          .mockResolvedValue(buildResponse([mockScanner, mockTriageAndRemediationProfile]));
        return createComponent();
      });

      it('opens from the change profile button with the applied profile', async () => {
        findChangeButton().vm.$emit('click');
        await nextTick();

        expect(findDrawer().props()).toMatchObject({
          open: true,
          presetId: mockTriageAndRemediationProfile.id,
        });
      });

      it('closes when the drawer closes', async () => {
        findChangeButton().vm.$emit('click');
        await nextTick();
        findDrawer().vm.$emit('close');
        await nextTick();

        expect(findDrawer().props('open')).toBe(false);
      });
    });

    describe('the profile details drawer', () => {
      beforeEach(() => createComponent());

      it('is closed, and shows only the applied profile', () => {
        expect(findDetailsDrawer().props()).toMatchObject({
          open: false,
          detailsOnly: true,
          presetId: '',
          profile: null,
        });
      });
    });

    describe('when a profile is attached and the card asks to view it', () => {
      beforeEach(async () => {
        queryHandler.mockResolvedValue(buildResponse([mockTriageAndRemediationProfile]));
        await createComponent();
        findCard().vm.$emit('view-profile');
        await nextTick();
      });

      it('opens the details drawer with the applied profile, not the select drawer', () => {
        expect(findDetailsDrawer().props()).toMatchObject({
          open: true,
          presetId: mockTriageAndRemediationProfile.id,
        });
        expect(findDrawer().props('open')).toBe(false);
      });

      it('closes and returns focus to the profile link when the drawer closes', async () => {
        findDetailsDrawer().vm.$emit('close');
        await nextTick();

        expect(findDetailsDrawer().props('open')).toBe(false);
        expect(focusProfileLink).toHaveBeenCalled();
      });
    });

    describe('when the drawer reports that it applied a profile', () => {
      beforeEach(async () => {
        queryHandler
          .mockResolvedValueOnce(buildResponse([]))
          .mockResolvedValue(buildResponse([mockTriageAndRemediationProfile]));
        await createComponent();
        findDrawer().vm.$emit('applied');
        await waitForPromises();
      });

      it('refetches the project and shows the applied profile', () => {
        expect(queryHandler).toHaveBeenCalledTimes(2);
        expect(findCard().props('profile')).toMatchObject({
          id: mockTriageAndRemediationProfile.id,
        });
      });
    });
  });

  describe('removing the attached profile', () => {
    beforeEach(() => {
      queryHandler
        .mockResolvedValueOnce(buildResponse([mockTriageAndRemediationProfile]))
        .mockResolvedValue(buildResponse([]));
    });

    it('shows the remove button next to change profile', async () => {
      await createComponent();

      expect(findRemoveButton().props('icon')).toBe('remove');
      expect(findRemoveButton().attributes('aria-label')).toBe('Remove profile');
    });

    it('hides the remove button when the user cannot apply profiles', async () => {
      await createComponent({ provide: { canApplyProfiles: false } });

      expect(findRemoveButton().exists()).toBe(false);
    });

    it('hides the remove button when no profile is attached', async () => {
      queryHandler.mockReset().mockResolvedValue(buildResponse([]));
      await createComponent();

      expect(findRemoveButton().exists()).toBe(false);
    });

    describe('when the user confirms', () => {
      beforeEach(async () => {
        await createComponent();
        findRemoveButton().vm.$emit('click');
        await waitForPromises();
      });

      it('asks for confirmation naming the profile and the project', () => {
        expect(confirmAction).toHaveBeenCalledWith(
          'Automated Triage and Remediation stops acting on vulnerabilities in this project. Merge requests it already opened stay open.',
          expect.objectContaining({
            title: 'Remove Standard from project?',
            primaryBtnText: 'Remove profile',
            primaryBtnVariant: 'danger',
          }),
        );
      });

      it('detaches the profile from the project', () => {
        expect(detachHandler).toHaveBeenCalledWith({
          input: {
            securityScanProfileId: mockTriageAndRemediationProfile.id,
            projectIds: ['gid://gitlab/Project/1'],
          },
        });
      });

      it('shows a toast', () => {
        expect(showToast).toHaveBeenCalledWith('Standard removed from project.');
      });

      it('refetches the project and shows the empty state', () => {
        expect(queryHandler).toHaveBeenCalledTimes(2);
        expect(findCard().props('profile')).toBeNull();
        expect(findRemoveError().exists()).toBe(false);
      });
    });

    describe('when the user cancels', () => {
      beforeEach(async () => {
        confirmAction.mockResolvedValue(false);
        await createComponent();
        findRemoveButton().vm.$emit('click');
        await waitForPromises();
      });

      it('does not detach the profile', () => {
        expect(detachHandler).not.toHaveBeenCalled();
        expect(showToast).not.toHaveBeenCalled();
        expect(findCard().props('profile')).not.toBeNull();
      });
    });

    describe('when the mutation returns errors', () => {
      beforeEach(async () => {
        detachHandler.mockResolvedValue({
          data: {
            securityScanProfileDetach: {
              clientMutationId: null,
              errors: ['Not allowed', 'Try again'],
              __typename: 'SecurityScanProfileDetachPayload',
            },
          },
        });
        queryHandler
          .mockReset()
          .mockResolvedValue(buildResponse([mockTriageAndRemediationProfile]));
        await createComponent();
        findRemoveButton().vm.$emit('click');
        await waitForPromises();
      });

      it('shows the errors and keeps the profile', () => {
        expect(findRemoveError().text()).toBe('Not allowed, Try again');
        expect(showToast).not.toHaveBeenCalled();
        expect(findCard().props('profile')).not.toBeNull();
      });
    });

    describe('when the request fails', () => {
      const error = new Error('boom');

      beforeEach(async () => {
        detachHandler.mockRejectedValue(error);
        queryHandler
          .mockReset()
          .mockResolvedValue(buildResponse([mockTriageAndRemediationProfile]));
        await createComponent();
        findRemoveButton().vm.$emit('click');
        await waitForPromises();
      });

      it('shows an error, reports it and keeps the profile', () => {
        expect(findRemoveError().text()).toBe('Failed to remove the profile.');
        expect(showToast).not.toHaveBeenCalled();
        expect(Sentry.captureException).toHaveBeenCalledWith(error);
        expect(findCard().props('profile')).not.toBeNull();
      });
    });
  });

  describe('when the query fails', () => {
    const error = new Error('boom');

    beforeEach(() => {
      queryHandler.mockRejectedValue(error);
      return createComponent();
    });

    it('shows an error and reports it', () => {
      expect(wrapper.findComponent(GlAlert).text()).toContain(
        'Failed to load triage and remediation profiles.',
      );
      expect(findCard().exists()).toBe(false);
      expect(Sentry.captureException).toHaveBeenCalledWith(error);
    });

    describe('and a later refetch succeeds', () => {
      beforeEach(async () => {
        queryHandler.mockResolvedValue(buildResponse([mockTriageAndRemediationProfile]));
        await wrapper.vm.$apollo.queries.project.refetch();
        await waitForPromises();
      });

      it('clears the error and shows the card', () => {
        expect(wrapper.findComponent(GlAlert).exists()).toBe(false);
        expect(findCard().props('profile')).toMatchObject({
          id: mockTriageAndRemediationProfile.id,
        });
      });
    });
  });
});
