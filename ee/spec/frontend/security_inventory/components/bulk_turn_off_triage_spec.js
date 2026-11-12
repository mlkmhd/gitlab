import Vue from 'vue';
import VueApollo from 'vue-apollo';
import { shallowMountExtended } from 'helpers/vue_test_utils_helper';
import createMockApollo from 'helpers/mock_apollo_helper';
import waitForPromises from 'helpers/wait_for_promises';
import { createAlert } from '~/alert';
import { confirmAction } from '~/lib/utils/confirm_via_gl_modal/confirm_via_gl_modal';
import * as Sentry from '~/sentry/sentry_browser_wrapper';
import {
  SCAN_PROFILE_TYPE_SAST,
  SCAN_PROFILE_TYPE_TRIAGE_AND_REMEDIATION,
} from '~/security_configuration/constants';
import BulkTurnOffTriage from 'ee/security_inventory/components/bulk_turn_off_triage.vue';
import groupAvailableSecurityScanProfilesQuery from 'ee/security_configuration/graphql/scan_profiles/group_available_security_scan_profiles.query.graphql';
import detachMutation from 'ee/security_configuration/graphql/scan_profiles/security_scan_profile_detach.mutation.graphql';

Vue.use(VueApollo);

jest.mock('~/alert');
jest.mock('~/lib/utils/confirm_via_gl_modal/confirm_via_gl_modal');
jest.mock('~/sentry/sentry_browser_wrapper');

const GROUP_FULL_PATH = 'my-group';
const GROUP_ID = 'gid://gitlab/Group/1';
const PROJECT_IDS = ['gid://gitlab/Project/2', 'gid://gitlab/Project/3'];

const profile = (name, scanType) => ({
  id: `gid://gitlab/Security::ScanProfile/${name}`,
  name,
  description: `The ${name} profile`,
  scanType,
  gitlabRecommended: true,
  triggers: [],
  triggerSettings: [],
  projectCount: 0,
  __typename: 'ScanProfileType',
});

const preset = (name) => profile(name, SCAN_PROFILE_TYPE_TRIAGE_AND_REMEDIATION);

const presets = [preset('conservative'), preset('standard'), preset('proactive')];
const sastProfile = profile('sast', SCAN_PROFILE_TYPE_SAST);

describe('BulkTurnOffTriage', () => {
  let wrapper;
  let profilesHandler;
  let detachHandler;
  let toastShow;

  const buildProfilesResponse = (profiles) => ({
    data: {
      group: {
        id: 'gid://gitlab/Group/100',
        name: GROUP_FULL_PATH,
        userPermissions: {
          createSecurityScanProfiles: false,
          updateSecurityScanProfiles: false,
          deleteSecurityScanProfiles: false,
          __typename: 'GroupPermissions',
        },
        availableSecurityScanProfiles: profiles,
        __typename: 'Group',
      },
    },
  });

  const createComponent = ({ itemIds = [GROUP_ID, ...PROJECT_IDS] } = {}) => {
    wrapper = shallowMountExtended(BulkTurnOffTriage, {
      apolloProvider: createMockApollo([
        [groupAvailableSecurityScanProfilesQuery, profilesHandler],
        [detachMutation, detachHandler],
      ]),
      propsData: { itemIds },
      provide: { groupFullPath: GROUP_FULL_PATH },
      mocks: { $toast: { show: toastShow } },
    });
  };

  const turnOff = async () => {
    wrapper.vm.turnOff();
    await waitForPromises();
  };

  beforeEach(() => {
    toastShow = jest.fn();
    profilesHandler = jest.fn().mockResolvedValue(buildProfilesResponse([...presets, sastProfile]));
    detachHandler = jest.fn().mockResolvedValue({
      data: { securityScanProfileDetach: { clientMutationId: null, errors: [] } },
    });
    confirmAction.mockResolvedValue(true);
  });

  it('asks for confirmation naming the selection', async () => {
    createComponent();
    await turnOff();

    expect(confirmAction).toHaveBeenCalledWith(
      "New vulnerabilities aren't triaged or fixed. Merge requests it already opened stay open.",
      {
        title: 'Turn off Automated Triage and Remediation for 1 subgroup and 2 projects?',
        primaryBtnText: 'Turn off',
        primaryBtnVariant: 'danger',
        size: 'md',
      },
    );
  });

  describe('when the user cancels', () => {
    beforeEach(async () => {
      confirmAction.mockResolvedValue(false);
      createComponent();
      await turnOff();
    });

    it('changes nothing', () => {
      expect(profilesHandler).not.toHaveBeenCalled();
      expect(detachHandler).not.toHaveBeenCalled();
      expect(toastShow).not.toHaveBeenCalled();
    });

    it('emits nothing, so the selection is kept', () => {
      expect(wrapper.emitted()).toEqual({});
    });
  });

  describe('when the user confirms', () => {
    beforeEach(async () => {
      createComponent();
      await turnOff();
    });

    it('loads the presets of the root group', () => {
      expect(profilesHandler).toHaveBeenCalledWith({
        fullPath: GROUP_FULL_PATH,
        gitlabRecommended: true,
      });
    });

    it('detaches every triage and remediation preset from the selection, one at a time', () => {
      expect(detachHandler.mock.calls.map(([{ input }]) => input)).toEqual(
        presets.map(({ id }) => ({
          securityScanProfileId: id,
          groupIds: [GROUP_ID],
          projectIds: PROJECT_IDS,
        })),
      );
    });

    it('does not detach profiles of other types', () => {
      expect(detachHandler).not.toHaveBeenCalledWith(
        expect.objectContaining({
          input: expect.objectContaining({ securityScanProfileId: sastProfile.id }),
        }),
      );
    });

    it('shows a toast and tells the table to clear the selection and refetch', () => {
      expect(toastShow).toHaveBeenCalledWith(
        'Automated Triage and Remediation turned off for 1 subgroup and 2 projects',
      );
      expect(wrapper.emitted('turned-off')).toHaveLength(1);
      expect(createAlert).not.toHaveBeenCalled();
    });
  });

  it('words a single project in the toast', async () => {
    createComponent({ itemIds: [PROJECT_IDS[0]] });
    await turnOff();

    expect(toastShow).toHaveBeenCalledWith(
      'Automated Triage and Remediation turned off for 1 project',
    );
  });

  describe('when a detach returns errors', () => {
    beforeEach(async () => {
      detachHandler
        .mockResolvedValueOnce({
          data: { securityScanProfileDetach: { clientMutationId: null, errors: [] } },
        })
        .mockResolvedValueOnce({
          data: { securityScanProfileDetach: { clientMutationId: null, errors: ['No access'] } },
        });
      createComponent();
      await turnOff();
    });

    it('lists the errors in an alert', () => {
      expect(createAlert).toHaveBeenCalledWith({ message: 'No access' });
    });

    it('does not show the toast or clear the selection, and refetches', () => {
      expect(toastShow).not.toHaveBeenCalled();
      expect(wrapper.emitted('turned-off')).toBeUndefined();
      expect(wrapper.emitted('refetch')).toHaveLength(1);
    });
  });

  describe('when a request fails', () => {
    const error = new Error('boom');

    beforeEach(async () => {
      profilesHandler.mockRejectedValue(error);
      createComponent();
      await turnOff();
    });

    it('shows an alert and reports the error', () => {
      expect(createAlert).toHaveBeenCalledWith({
        message: 'Failed to turn off Automated Triage and Remediation.',
      });
      expect(Sentry.captureException).toHaveBeenCalledWith(error);
    });

    it('detaches nothing and refetches', () => {
      expect(detachHandler).not.toHaveBeenCalled();
      expect(wrapper.emitted('refetch')).toHaveLength(1);
    });
  });

  it('ignores a second request while one is running', async () => {
    createComponent();
    wrapper.vm.turnOff();
    wrapper.vm.turnOff();
    await waitForPromises();

    expect(confirmAction).toHaveBeenCalledTimes(1);
  });
});
