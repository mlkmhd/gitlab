import Vue, { nextTick } from 'vue';
import VueApollo from 'vue-apollo';
import { GlDrawer, GlTab } from '@gitlab/ui';
import { shallowMountExtended } from 'helpers/vue_test_utils_helper';
import { stubComponent } from 'helpers/stub_component';
import createMockApollo from 'helpers/mock_apollo_helper';
import waitForPromises from 'helpers/wait_for_promises';
import { createAlert } from '~/alert';
import { confirmAction } from '~/lib/utils/confirm_via_gl_modal/confirm_via_gl_modal';
import * as Sentry from '~/sentry/sentry_browser_wrapper';
import CrudComponent from '~/vue_shared/components/crud_component.vue';
import TriageProfileDrawer from 'ee/security_configuration/components/scan_profiles/triage_profile_drawer.vue';
import ProfileListDrawer from 'ee/security_configuration/components/scan_profiles/profile_list_drawer.vue';
import TriagePresetCapabilities from 'ee/security_configuration/components/scan_profiles/triage_preset_capabilities.vue';
import groupAvailableSecurityScanProfilesQuery from 'ee/security_configuration/graphql/scan_profiles/group_available_security_scan_profiles.query.graphql';
import attachMutation from 'ee/security_configuration/graphql/scan_profiles/security_scan_profile_attach.mutation.graphql';
import {
  SCAN_PROFILE_TYPE_SECRET_DETECTION,
  SCAN_PROFILE_TYPE_TRIAGE_AND_REMEDIATION,
} from '~/security_configuration/constants';

Vue.use(VueApollo);

jest.mock('~/alert');
jest.mock('~/lib/utils/confirm_via_gl_modal/confirm_via_gl_modal');

const GROUP_FULL_PATH = 'my-group';

describe('TriageProfileDrawer', () => {
  let wrapper;
  let resolver;
  let attachHandler;

  const buildPreset = (preset, name, overrides = {}) => ({
    id: `gid://gitlab/Security::ScanProfile/triage_and_remediation_${preset}`,
    name,
    description: `The ${preset} preset`,
    scanType: SCAN_PROFILE_TYPE_TRIAGE_AND_REMEDIATION,
    gitlabRecommended: true,
    triggers: [],
    triggerSettings: [],
    projectCount: 0,
    __typename: 'ScanProfileType',
    ...overrides,
  });

  const conservative = buildPreset('conservative', 'Triage and Remediation (Conservative)');
  const standard = buildPreset('standard', 'Triage and Remediation (Standard)', {
    triggers: ['SAST_FALSE_POSITIVE', 'SAST_VULNERABILITY_RESOLUTION'],
    triggerSettings: [
      {
        triggerType: 'SAST_FALSE_POSITIVE',
        configuration: {
          severityLevel: 'MEDIUM',
          runMode: 'AUTO',
          __typename: 'SastFalsePositiveConfiguration',
        },
        __typename: 'ScanProfileTriggerSetting',
      },
    ],
  });
  const proactive = buildPreset('proactive', 'Triage and Remediation (Proactive)', {
    triggers: ['SBOM_INGESTED'],
  });
  const secretDetection = buildPreset('secret', 'Secret Detection (default)', {
    id: 'gid://gitlab/Security::ScanProfile/secret_detection',
    scanType: SCAN_PROFILE_TYPE_SECRET_DETECTION,
  });

  const createResolver = (profiles = [conservative, secretDetection, standard, proactive]) =>
    jest.fn().mockResolvedValue({
      data: {
        group: {
          id: 'gid://gitlab/Group/1',
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

  const createAttachHandler = (errors = []) =>
    jest.fn().mockResolvedValue({
      data: { securityScanProfileAttach: { clientMutationId: null, errors } },
    });

  const createComponent = ({
    props = {},
    queryResolver = createResolver(),
    mutationHandler = createAttachHandler(),
  } = {}) => {
    resolver = queryResolver;
    attachHandler = mutationHandler;

    wrapper = shallowMountExtended(TriageProfileDrawer, {
      apolloProvider: createMockApollo([
        [groupAvailableSecurityScanProfilesQuery, resolver],
        [attachMutation, attachHandler],
      ]),
      propsData: {
        open: true,
        ...props,
      },
      provide: {
        groupFullPath: GROUP_FULL_PATH,
      },
      mocks: {
        $toast: { show: jest.fn() },
      },
      stubs: {
        CrudComponent,
        ProfileListDrawer,
        GlDrawer: stubComponent(GlDrawer, {
          template: '<div><slot name="title" /><slot /></div>',
        }),
      },
    });
  };

  const findListItems = () => wrapper.findAllByTestId('triage-profile-list-item');
  const findSelectedItem = () => wrapper.find('[aria-current="true"]');
  const findDetail = () => wrapper.findByTestId('triage-profile-detail');
  const findItemByName = (name) =>
    findListItems().wrappers.find((item) => item.text().includes(name));

  const findBadge = (name, testId) => findItemByName(name).find(`[data-testid="${testId}"]`);
  const findAppliedBadges = () => wrapper.findAllByTestId('applied-badge');
  const findDetailValues = () =>
    findDetail()
      .findAll('dd')
      .wrappers.map((cell) => cell.text());
  const findApplyButton = () => wrapper.findComponentByTestId('apply-profile-button');
  const findApplyButtonWrapper = () => wrapper.findByTestId('apply-profile-button-wrapper');
  const project = { id: 'gid://gitlab/Project/1' };

  it('fetches the recommended profiles of the group', async () => {
    createComponent();
    await waitForPromises();

    expect(resolver).toHaveBeenCalledWith({ fullPath: GROUP_FULL_PATH, gitlabRecommended: true });
  });

  it('renders the triage and remediation presets', async () => {
    createComponent();
    await waitForPromises();

    expect(findListItems()).toHaveLength(3);
    expect(wrapper.text()).not.toContain(secretDetection.name);
  });

  describe('with no preset passed', () => {
    beforeEach(async () => {
      createComponent();
      await waitForPromises();
    });

    it('renders Standard as current', () => {
      expect(findSelectedItem().text()).toContain(standard.name);
    });

    it('shows the details of Standard', () => {
      expect(findDetail().text()).toContain(standard.description);
    });

    it('renders the general details of Standard', () => {
      expect(findDetailValues()).toEqual([
        'The standard preset',
        'Automated Triage and Remediation',
        'GitLab',
      ]);
    });

    it('shows the Recommended badge beside the heading', () => {
      expect(wrapper.findByTestId('detail-recommended-badge').text()).toBe('Recommended');
      expect(wrapper.findByTestId('detail-applied-badge').exists()).toBe(false);
    });

    it('passes the triggers of Standard', () => {
      expect(wrapper.findComponent(TriagePresetCapabilities).props()).toEqual({
        triggers: standard.triggers,
        triggerSettings: standard.triggerSettings,
      });
    });

    it('renders the tab titled Configuration', () => {
      expect(wrapper.findComponent(GlTab).attributes('title')).toBe('Configuration');
    });

    it('shows the Recommended badge on Standard', () => {
      expect(wrapper.findAllByTestId('recommended-badge')).toHaveLength(1);
      expect(findBadge(standard.name, 'recommended-badge').exists()).toBe(true);
    });

    it('hides the Applied badge', () => {
      expect(findAppliedBadges()).toHaveLength(0);
    });

    describe('and a preset clicked', () => {
      beforeEach(async () => {
        await findItemByName(conservative.name).trigger('click');
      });

      it('renders the clicked preset as current', () => {
        expect(findSelectedItem().text()).toContain(conservative.name);
      });

      it('shows the details of the clicked preset', () => {
        expect(findDetail().text()).toContain(conservative.description);
      });

      it('passes the triggers of the clicked preset', () => {
        expect(wrapper.findComponent(TriagePresetCapabilities).props('triggers')).toEqual(
          conservative.triggers,
        );
      });

      it('hides the badge beside the heading', () => {
        expect(wrapper.findByTestId('detail-recommended-badge').exists()).toBe(false);
        expect(wrapper.findByTestId('detail-applied-badge').exists()).toBe(false);
      });

      it('resets to Standard on reopen', async () => {
        await wrapper.setProps({ open: false });
        await wrapper.setProps({ open: true });
        await waitForPromises();

        expect(findSelectedItem().text()).toContain(standard.name);
      });
    });
  });

  describe('with a preset passed', () => {
    beforeEach(async () => {
      createComponent({ props: { presetId: proactive.id } });
      await waitForPromises();
    });

    it('renders the passed preset as current', () => {
      expect(findSelectedItem().text()).toContain(proactive.name);
      expect(findDetail().text()).toContain(proactive.description);
    });

    it('hides the Applied badge', () => {
      expect(findAppliedBadges()).toHaveLength(0);
    });

    it('resets to the passed preset on reopen', async () => {
      await findItemByName(conservative.name).trigger('click');
      await wrapper.setProps({ open: false });
      await wrapper.setProps({ open: true });
      await waitForPromises();

      expect(findSelectedItem().text()).toContain(proactive.name);
    });
  });

  describe('with a project passed', () => {
    it('shows the Applied badge on its preset', async () => {
      createComponent({ props: { project, presetId: proactive.id } });
      await waitForPromises();

      expect(findAppliedBadges()).toHaveLength(1);
      expect(findBadge(proactive.name, 'applied-badge').exists()).toBe(true);
    });

    it('shows Applied in place of Recommended', async () => {
      createComponent({ props: { project, presetId: standard.id } });
      await waitForPromises();

      expect(findBadge(standard.name, 'applied-badge').exists()).toBe(true);
      expect(findBadge(standard.name, 'recommended-badge').exists()).toBe(false);
    });

    it('shows Applied beside the heading', async () => {
      createComponent({ props: { project, presetId: standard.id } });
      await waitForPromises();

      expect(wrapper.findByTestId('detail-applied-badge').text()).toBe('Applied');
      expect(wrapper.findByTestId('detail-recommended-badge').exists()).toBe(false);
    });

    it('hides the Applied badge with no preset', async () => {
      createComponent({ props: { project } });
      await waitForPromises();

      expect(findAppliedBadges()).toHaveLength(0);
    });
  });

  describe('with details only', () => {
    beforeEach(async () => {
      createComponent({
        props: { project, presetId: proactive.id, profile: proactive, detailsOnly: true },
      });
      await waitForPromises();
    });

    it('titles the drawer as the profile details', () => {
      expect(wrapper.findComponent(ProfileListDrawer).props('title')).toBe(
        'Automated Triage and Remediation profile details',
      );
    });

    it('hides the profile list and uses the narrow layout', () => {
      expect(wrapper.findComponent(ProfileListDrawer).props()).toMatchObject({
        showList: false,
        narrow: true,
      });
      expect(findListItems()).toHaveLength(0);
    });

    it('shows only the details of the passed profile', () => {
      expect(findDetail().text()).toContain(proactive.name);
      expect(findDetail().text()).toContain(proactive.description);
    });

    it('hides the Apply profile button', () => {
      expect(findApplyButton().exists()).toBe(false);
    });

    it('does not load the group profiles', () => {
      expect(resolver).not.toHaveBeenCalled();
    });

    describe('when the profile is not GitLab-recommended', () => {
      const custom = buildPreset('custom', 'Custom triage profile', { gitlabRecommended: false });

      beforeEach(async () => {
        createComponent({
          props: { project, presetId: custom.id, profile: custom, detailsOnly: true },
        });
        await waitForPromises();
      });

      it('shows that profile instead of another preset', () => {
        expect(findDetail().text()).toContain(custom.name);
        expect(findDetail().text()).not.toContain(standard.name);
      });
    });
  });

  describe('applying a preset', () => {
    const apply = async () => {
      findApplyButton().vm.$emit('click');
      await waitForPromises();
    };

    it('hides the Apply profile button without a project', async () => {
      createComponent();
      await waitForPromises();

      expect(findApplyButton().exists()).toBe(false);
    });

    describe('with no preset applied', () => {
      beforeEach(async () => {
        createComponent({ props: { project } });
        await waitForPromises();
        await findItemByName(proactive.name).trigger('click');
        await apply();
      });

      it('applies the selected preset without confirming', () => {
        expect(confirmAction).not.toHaveBeenCalled();
        expect(attachHandler).toHaveBeenCalledWith({
          input: {
            securityScanProfileId: proactive.id,
            groupIds: [],
            projectIds: [project.id],
          },
        });
      });

      it('shows a toast', () => {
        expect(wrapper.vm.$toast.show).toHaveBeenCalledWith('Profile applied successfully.');
      });

      it('emits applied and close', () => {
        expect(wrapper.emitted('applied')).toEqual([[proactive]]);
        expect(wrapper.emitted('close')).toHaveLength(1);
      });
    });

    it('sets the button loading while applying', async () => {
      createComponent({
        props: { project },
        mutationHandler: jest.fn(() => new Promise(() => {})),
      });
      await waitForPromises();
      await apply();

      expect(findApplyButton().props('loading')).toBe(true);
    });

    it('keeps the drawer open on Esc while applying', async () => {
      createComponent({
        props: { project },
        mutationHandler: jest.fn(() => new Promise(() => {})),
      });
      await waitForPromises();
      await apply();

      wrapper.findComponent(GlDrawer).vm.$emit('close');

      expect(wrapper.emitted('close')).toBeUndefined();
    });

    describe('with the applied preset selected', () => {
      beforeEach(async () => {
        createComponent({ props: { project, presetId: standard.id } });
        await waitForPromises();
      });

      it('disables the Apply profile button', () => {
        expect(findApplyButton().props('disabled')).toBe(true);
      });

      it('shows the already applied tooltip', () => {
        expect(findApplyButtonWrapper().attributes('title')).toBe(
          'This profile is already applied.',
        );
      });
    });

    describe('with another preset applied', () => {
      beforeEach(async () => {
        createComponent({ props: { project, presetId: standard.id } });
        await waitForPromises();
        await findItemByName(proactive.name).trigger('click');
      });

      it('enables the Apply profile button', () => {
        expect(findApplyButton().props('disabled')).toBe(false);
      });

      it('shows no tooltip', () => {
        expect(findApplyButtonWrapper().attributes('title')).toBe('');
      });

      it('shows a switch confirmation', async () => {
        await apply();

        expect(confirmAction).toHaveBeenCalledWith(
          `New vulnerabilities use ${proactive.name}. Existing ones keep what ${standard.name} already did.`,
          { title: `Switch to ${proactive.name}?`, primaryBtnText: 'Switch profile' },
        );
      });

      it('shows one confirmation on a double click', async () => {
        confirmAction.mockReturnValueOnce(new Promise(() => {}));
        findApplyButton().vm.$emit('click');
        findApplyButton().vm.$emit('click');
        await nextTick();

        expect(confirmAction).toHaveBeenCalledTimes(1);
      });

      it('applies the preset on confirm', async () => {
        confirmAction.mockResolvedValueOnce(true);
        await apply();

        expect(attachHandler).toHaveBeenCalledWith({
          input: {
            securityScanProfileId: proactive.id,
            groupIds: [],
            projectIds: [project.id],
          },
        });
      });

      it('applies nothing on cancel', async () => {
        confirmAction.mockResolvedValueOnce(false);
        await apply();

        expect(attachHandler).not.toHaveBeenCalled();
      });

      it('keeps the drawer open on Esc while confirming', async () => {
        confirmAction.mockReturnValueOnce(new Promise(() => {}));
        findApplyButton().vm.$emit('click');
        await nextTick();

        wrapper.findComponent(GlDrawer).vm.$emit('close');

        expect(wrapper.emitted('close')).toBeUndefined();
      });

      it('emits close on Esc after a cancelled switch', async () => {
        confirmAction.mockResolvedValueOnce(false);
        await apply();

        wrapper.findComponent(GlDrawer).vm.$emit('close');

        expect(wrapper.emitted('close')).toHaveLength(1);
      });
    });

    describe('with mutation errors', () => {
      beforeEach(async () => {
        createComponent({
          props: { project },
          mutationHandler: createAttachHandler(['Project is at its limit']),
        });
        await waitForPromises();
        await apply();
      });

      it('shows the errors in an alert', () => {
        expect(createAlert).toHaveBeenCalledWith({
          message: 'Project is at its limit',
          containerSelector: '.js-triage-profile-drawer-flash-container',
        });
      });

      it('keeps the drawer open', () => {
        expect(wrapper.emitted('close')).toBeUndefined();
        expect(wrapper.emitted('applied')).toBeUndefined();
      });
    });

    describe('with a failed mutation', () => {
      const error = new Error('Network error');

      beforeEach(async () => {
        jest.spyOn(Sentry, 'captureException');
        createComponent({
          props: { project },
          mutationHandler: jest.fn().mockRejectedValue(error),
        });
        await waitForPromises();
        await apply();
      });

      it('shows an alert', () => {
        expect(createAlert).toHaveBeenCalledWith({
          message: 'Error applying profile. Please try again.',
          containerSelector: '.js-triage-profile-drawer-flash-container',
        });
      });

      it('passes the error to Sentry', () => {
        expect(Sentry.captureException).toHaveBeenCalledWith(
          expect.objectContaining({ networkError: error }),
        );
      });

      it('keeps the drawer open', () => {
        expect(wrapper.emitted('close')).toBeUndefined();
      });
    });
  });

  describe('with items passed', () => {
    const group = 'gid://gitlab/Group/2';
    const otherGroup = 'gid://gitlab/Group/3';
    const otherProject = 'gid://gitlab/Project/2';
    const bulkItemIds = [group, project.id, otherProject];

    const findProfileListDrawer = () => wrapper.findComponent(ProfileListDrawer);
    const apply = async () => {
      findApplyButton().vm.$emit('click');
      await waitForPromises();
    };

    it.each`
      ids                    | title
      ${[project.id]}        | ${'Select an Automated Triage and Remediation profile for 1 item'}
      ${[group, project.id]} | ${'Select an Automated Triage and Remediation profile for 2 items'}
    `('titles the drawer "$title"', async ({ ids, title }) => {
      createComponent({ props: { bulkItemIds: ids } });
      await waitForPromises();

      expect(findProfileListDrawer().props('title')).toBe(title);
    });

    it('shows the Apply profile button', async () => {
      createComponent({ props: { bulkItemIds } });
      await waitForPromises();

      expect(findApplyButton().text()).toBe('Apply profile');
      expect(findApplyButton().props('disabled')).toBe(false);
    });

    it.each`
      ids                                  | selection
      ${[project.id]}                      | ${'1 project'}
      ${[project.id, otherProject]}        | ${'2 projects'}
      ${[group]}                           | ${'1 subgroup'}
      ${[group, otherGroup]}               | ${'2 subgroups'}
      ${[group, project.id, otherProject]} | ${'1 subgroup and 2 projects'}
    `('confirms applying to "$selection"', async ({ ids, selection }) => {
      createComponent({ props: { bulkItemIds: ids } });
      await waitForPromises();
      await apply();

      expect(confirmAction).toHaveBeenCalledWith(`${standard.name} uses GitLab Credits.`, {
        title: `Apply ${standard.name} to ${selection}?`,
        primaryBtnText: 'Apply profile',
      });
    });

    it('hides the drawer while confirming', async () => {
      confirmAction.mockReturnValueOnce(new Promise(() => {}));
      createComponent({ props: { bulkItemIds } });
      await waitForPromises();
      await apply();

      expect(findProfileListDrawer().props('open')).toBe(false);
    });

    describe('on cancel', () => {
      beforeEach(async () => {
        confirmAction.mockResolvedValueOnce(false);
        createComponent({ props: { bulkItemIds } });
        await waitForPromises();
        await apply();
      });

      it('applies nothing', () => {
        expect(attachHandler).not.toHaveBeenCalled();
        expect(wrapper.emitted('applied')).toBeUndefined();
      });

      it('emits close', () => {
        expect(wrapper.emitted('close')).toHaveLength(1);
      });
    });

    describe('on confirm', () => {
      beforeEach(async () => {
        confirmAction.mockResolvedValueOnce(true);
        createComponent({ props: { bulkItemIds } });
        await waitForPromises();
        await findItemByName(proactive.name).trigger('click');
        await apply();
      });

      it('applies the preset to the selected items', () => {
        expect(attachHandler).toHaveBeenCalledWith({
          input: {
            securityScanProfileId: proactive.id,
            groupIds: [group],
            projectIds: [project.id, otherProject],
          },
        });
      });

      it('shows a toast naming the preset and the selection', () => {
        expect(wrapper.vm.$toast.show).toHaveBeenCalledWith(
          `${proactive.name} applied to 1 subgroup and 2 projects.`,
        );
      });

      it('emits applied and close', () => {
        expect(wrapper.emitted('applied')).toEqual([[proactive]]);
        expect(wrapper.emitted('close')).toHaveLength(1);
      });
    });

    describe('with mutation errors', () => {
      beforeEach(async () => {
        confirmAction.mockResolvedValueOnce(true);
        createComponent({
          props: { bulkItemIds },
          mutationHandler: createAttachHandler(['Project A is at its limit', 'Project B failed']),
        });
        await waitForPromises();
        await findItemByName(proactive.name).trigger('click');
        await apply();
      });

      it('shows the drawer on the chosen preset', () => {
        expect(findProfileListDrawer().props('open')).toBe(true);
        expect(findSelectedItem().text()).toContain(proactive.name);
      });

      it('shows the errors in an alert', () => {
        expect(createAlert).toHaveBeenCalledWith({
          message: 'Project A is at its limit, Project B failed',
          containerSelector: '.js-triage-profile-drawer-flash-container',
        });
      });

      it('emits neither applied nor close', () => {
        expect(wrapper.emitted('applied')).toBeUndefined();
        expect(wrapper.emitted('close')).toBeUndefined();
      });
    });

    describe('with a failed mutation', () => {
      beforeEach(async () => {
        confirmAction.mockResolvedValueOnce(true);
        createComponent({
          props: { bulkItemIds },
          mutationHandler: jest.fn().mockRejectedValue(new Error('Network error')),
        });
        await waitForPromises();
        await apply();
      });

      it('shows the drawer with an alert', () => {
        expect(findProfileListDrawer().props('open')).toBe(true);
        expect(createAlert).toHaveBeenCalledWith({
          message: 'Error applying profile. Please try again.',
          containerSelector: '.js-triage-profile-drawer-flash-container',
        });
      });
    });
  });

  it('fetches nothing while closed', async () => {
    createComponent({ props: { open: false } });
    await waitForPromises();

    expect(resolver).not.toHaveBeenCalled();
  });

  describe('with no Standard in the data', () => {
    it('renders the first preset as current', async () => {
      createComponent({ queryResolver: createResolver([conservative, proactive]) });
      await waitForPromises();

      expect(findSelectedItem().text()).toContain(conservative.name);
    });
  });

  describe('with no triage presets', () => {
    const findEmptyState = () => wrapper.findByTestId('triage-profile-empty');

    it.each`
      scenario                   | queryResolver
      ${'no profiles'}           | ${createResolver([])}
      ${'only other scan types'} | ${createResolver([secretDetection])}
      ${'no group'}              | ${jest.fn().mockResolvedValue({ data: { group: null } })}
    `('shows the empty state with $scenario', async ({ queryResolver }) => {
      createComponent({ queryResolver });
      await waitForPromises();

      expect(findEmptyState().exists()).toBe(true);
      expect(findListItems()).toHaveLength(0);
      expect(findDetail().exists()).toBe(false);
    });

    it('hides the empty state when presets exist', async () => {
      createComponent();
      await waitForPromises();

      expect(findEmptyState().exists()).toBe(false);
    });

    it('hides the empty state after a failed query', async () => {
      createComponent({ queryResolver: jest.fn().mockRejectedValue(new Error('Network error')) });
      await waitForPromises();

      expect(findEmptyState().exists()).toBe(false);
    });
  });

  describe('with a failed query', () => {
    const error = new Error('Network error');

    beforeEach(async () => {
      jest.spyOn(Sentry, 'captureException');
      createComponent({ queryResolver: jest.fn().mockRejectedValue(error) });
      await waitForPromises();
    });

    it('shows an alert', () => {
      expect(createAlert).toHaveBeenCalledWith({
        message: 'Failed to load triage and remediation profiles.',
        containerSelector: '.js-triage-profile-drawer-flash-container',
      });
    });

    it('passes the error to Sentry', () => {
      expect(Sentry.captureException).toHaveBeenCalled();
    });

    it('hides the list', () => {
      expect(wrapper.findByTestId('triage-profile-list').exists()).toBe(false);
    });
  });

  it('emits close on dismiss', () => {
    createComponent();

    wrapper.findComponent(GlDrawer).vm.$emit('close');

    expect(wrapper.emitted('close')).toHaveLength(1);
  });
});
