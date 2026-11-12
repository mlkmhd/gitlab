import Vue, { nextTick } from 'vue';
import VueApollo from 'vue-apollo';
import {
  GlBadge,
  GlButton,
  GlLink,
  GlPopover,
  GlSkeletonLoader,
  GlSprintf,
  GlTruncate,
} from '@gitlab/ui';
import { shallowMountExtended } from 'helpers/vue_test_utils_helper';
import createMockApollo from 'helpers/mock_apollo_helper';
import waitForPromises from 'helpers/wait_for_promises';
import * as Sentry from '~/sentry/sentry_browser_wrapper';
import { BV_HIDE_POPOVER } from '~/lib/utils/constants';
import CapabilitiesCell from 'ee/security_inventory/components/capabilities_cell.vue';
import GroupCapabilitiesIndicator from 'ee/security_inventory/components/group_capabilities_indicator.vue';
import ProjectSecurityScanProfilesQuery from 'ee/security_inventory/graphql/project_security_scan_profiles.query.graphql';
import { mockProjects, subgroupsSecurityDetails } from 'ee_jest/security_inventory/mock_data';

Vue.use(VueApollo);

describe('CapabilitiesCell', () => {
  let wrapper;
  let queryHandler;

  const mockProject = mockProjects[0];
  const mockGroup = subgroupsSecurityDetails.data.group.descendantGroups.nodes[0];

  const capability = (triggerType, enabled, runMode = 'MANUAL') => ({
    triggerType,
    enabled,
    runMode,
    flowStatus: 'AVAILABLE',
  });

  const withFlowStatus = (entry, flowStatus) => ({ ...entry, flowStatus });

  const profilesResponse = (securityScanProfiles) => ({
    data: {
      project: {
        __typename: 'Project',
        id: 'gid://gitlab/Project/1',
        securityScanProfiles: securityScanProfiles.map((profile) => ({
          __typename: 'ScanProfileType',
          ...profile,
        })),
      },
    },
  });

  const createComponent = ({
    item = mockProject,
    hideProfileActions = false,
    canApplyProfiles = true,
    canAdminRootGroup = false,
    duoSettingsPath = '',
    groupOwnersPath = '/groups/gitlab-org/-/group_members?max_role=static-50',
    securityScanProfiles = [
      {
        id: 'gid://gitlab/Security::ScanProfile/1',
        name: 'Secret Push Protection (Default)',
        scanType: 'SECRET_DETECTION',
      },
      {
        id: 'gid://gitlab/Security::ScanProfile/2',
        name: 'Triage and Remediation (Standard)',
        scanType: 'TRIAGE_AND_REMEDIATION',
      },
    ],
    handler = jest.fn().mockResolvedValue(profilesResponse(securityScanProfiles)),
  } = {}) => {
    queryHandler = handler;

    wrapper = shallowMountExtended(CapabilitiesCell, {
      apolloProvider: createMockApollo([[ProjectSecurityScanProfilesQuery, queryHandler]]),
      propsData: { item, hideProfileActions },
      provide: { canApplyProfiles, canAdminRootGroup, duoSettingsPath, groupOwnersPath },
      stubs: { GlBadge, GlButton, GlLink, GlPopover, GlSprintf, GlTruncate },
    });
  };

  const analyzerStatus = (analyzerType, status = 'SUCCESS') => ({ analyzerType, status });

  const runningScanners = [
    analyzerStatus('SAST'),
    analyzerStatus('SECRET_DETECTION'),
    analyzerStatus('DEPENDENCY_SCANNING'),
  ];

  const projectWith = (capabilities, analyzerStatuses = runningScanners) => ({
    ...mockProject,
    analyzerStatuses,
    triageAndRemediationCoverage: { capabilities },
  });

  const enabledProject = projectWith([
    capability('SAST_FALSE_POSITIVE', true, 'AUTO'),
    capability('SECRET_DETECTION_FALSE_POSITIVE', true, 'MANUAL'),
    capability('SBOM_INGESTED', false),
  ]);

  const findGroupIndicator = () => wrapper.findComponent(GroupCapabilitiesIndicator);
  const findBadge = () => wrapper.findComponent(GlBadge);
  const findPopover = () => wrapper.findComponent(GlPopover);
  const findProfileRow = () => wrapper.findByTestId('profile-row');
  const findSkeletonLoader = () => wrapper.findComponent(GlSkeletonLoader);
  const showPopover = () => findPopover().vm.$emit('show');
  const findRows = () =>
    wrapper
      .findAllByTestId('capability-row')
      .wrappers.map((row) => row.findAll('span').wrappers.map((span) => span.text()));
  const findOffForGroupStatuses = () => wrapper.findAllByTestId('off-for-group-status');
  const findDuoSettingsLink = () => wrapper.findByTestId('duo-settings-link');
  const findOffForGroupFooter = () => wrapper.findByTestId('off-for-group-footer');
  const findDescription = () => wrapper.findByTestId('not-enabled-description');
  const findApplyButton = () => wrapper.findComponentByTestId('apply-profile-button');
  const findChangeButton = () => wrapper.findComponentByTestId('change-profile-button');
  const findManageButton = () => wrapper.findComponentByTestId('manage-configuration-button');

  it('renders the group capabilities indicator for a group row', () => {
    createComponent({ item: mockGroup });

    expect(findGroupIndicator().props('item')).toEqual(mockGroup);
    expect(findBadge().exists()).toBe(false);
  });

  it('renders the badge as a popover button', () => {
    createComponent();

    expect(findBadge().attributes('id')).toBe(
      `capabilities-${mockProject.fullPath.replaceAll('/', '-')}`,
    );
    expect(findBadge().props('tag')).toBe('button');
    expect(findPopover().props()).toMatchObject({
      target: findBadge().attributes('id'),
      placement: 'top',
      title: 'Automated Triage and Remediation',
    });
  });

  describe('when a capability is enabled', () => {
    beforeEach(() => {
      createComponent({ item: enabledProject });
    });

    it('renders a green badge', () => {
      expect(findBadge().props('variant')).toBe('success');
      expect(findBadge().text()).toBe('Automated Triage and Remediation');
      expect(findBadge().attributes('aria-label')).toBe('Automated Triage and Remediation enabled');
    });

    it('renders each capability with its run mode', () => {
      expect(findRows()).toEqual([
        ['SAST false positive detection', 'Automatic'],
        ['SAST vulnerability resolution', 'Off'],
        ['Dependency scanning auto-remediation', 'Off'],
        ['Secret detection false positive detection', 'On demand'],
      ]);
    });

    it('does not explain how to turn it on', () => {
      expect(findDescription().exists()).toBe(false);
    });

    it('does not fetch the profile', () => {
      expect(queryHandler).not.toHaveBeenCalled();
      expect(findProfileRow().exists()).toBe(false);
    });

    describe('when the popover opens', () => {
      beforeEach(async () => {
        showPopover();
        await nextTick();
      });

      it('fetches the profiles of the project', () => {
        expect(queryHandler).toHaveBeenCalledWith({ fullPath: mockProject.fullPath });
      });

      it('renders the applied triage profile', async () => {
        await waitForPromises();

        expect(findSkeletonLoader().exists()).toBe(false);
        expect(findProfileRow().text()).toContain('Profile');
        expect(findProfileRow().findComponent(GlTruncate).props('text')).toBe(
          'Triage and Remediation (Standard)',
        );
      });

      it('emits the applied profile from Change profile', async () => {
        await waitForPromises();
        findChangeButton().vm.$emit('click');

        expect(wrapper.emitted('open-triage-drawer')).toEqual([
          [{ project: enabledProject, presetId: 'gid://gitlab/Security::ScanProfile/2' }],
        ]);
      });

      it('hides the popover from Change profile', () => {
        const onHide = jest.fn();
        wrapper.vm.$root.$on(BV_HIDE_POPOVER, onHide);
        findChangeButton().vm.$emit('click');

        expect(onHide).toHaveBeenCalledWith(findBadge().attributes('id'));
      });
    });

    describe('when the profile changes and the popover is reopened', () => {
      const profile = (name) => [
        { id: 'gid://gitlab/Security::ScanProfile/2', name, scanType: 'TRIAGE_AND_REMEDIATION' },
      ];

      beforeEach(async () => {
        const handler = jest
          .fn()
          .mockResolvedValueOnce(profilesResponse(profile('Triage and Remediation (Standard)')))
          .mockResolvedValueOnce(profilesResponse(profile('Triage and Remediation (Strict)')));
        createComponent({ item: enabledProject, handler });

        showPopover();
        await waitForPromises();
        findPopover().vm.$emit('hidden');
        await nextTick();
        showPopover();
        await waitForPromises();
      });

      it('fetches the profiles again', () => {
        expect(queryHandler).toHaveBeenCalledTimes(2);
      });

      it('renders the new profile', () => {
        expect(findProfileRow().findComponent(GlTruncate).props('text')).toBe(
          'Triage and Remediation (Strict)',
        );
      });
    });

    it('renders Change profile as the primary button', () => {
      expect(findChangeButton().text()).toBe('Change profile');
      expect(findChangeButton().props('variant')).toBe('confirm');
    });

    it('links Manage configuration to the triage tab', () => {
      expect(findManageButton().text()).toBe('Manage configuration');
      expect(findManageButton().attributes('href')).toBe(
        '/flightjs/security-reports-example/-/security/configuration?tab=automated-triage-and-remediation',
      );
    });

    it('does not render Apply profile', () => {
      expect(findApplyButton().exists()).toBe(false);
    });

    describe('when the user cannot apply profiles', () => {
      it('renders neither button', () => {
        createComponent({ item: enabledProject, canApplyProfiles: false });

        expect(findChangeButton().exists()).toBe(false);
        expect(findManageButton().exists()).toBe(false);
      });
    });

    describe('while the profile loads', () => {
      beforeEach(async () => {
        createComponent({ item: enabledProject, handler: jest.fn(() => new Promise(() => {})) });
        showPopover();
        await nextTick();
      });

      it('renders a skeleton in the Profile row', () => {
        expect(findProfileRow().text()).toBe('Profile');
        expect(findSkeletonLoader().exists()).toBe(true);
      });

      it('renders Change profile as loading', () => {
        expect(findChangeButton().props('loading')).toBe(true);
      });
    });

    describe('when the project has no triage profile', () => {
      it('does not render the Profile row', async () => {
        createComponent({
          item: enabledProject,
          securityScanProfiles: [
            {
              id: 'gid://gitlab/Security::ScanProfile/1',
              name: 'Secret Push Protection (Default)',
              scanType: 'SECRET_DETECTION',
            },
          ],
        });
        showPopover();
        await waitForPromises();

        expect(findProfileRow().exists()).toBe(false);
        expect(findRows()).toHaveLength(4);
      });
    });

    describe('when the profile query fails', () => {
      const error = new Error('boom');

      beforeEach(async () => {
        jest.spyOn(Sentry, 'captureException').mockImplementation();
        createComponent({
          item: enabledProject,
          handler: jest.fn().mockRejectedValue(error),
        });
        showPopover();
        await waitForPromises();
      });

      it('does not render the Profile row', () => {
        expect(findSkeletonLoader().exists()).toBe(false);
        expect(findProfileRow().exists()).toBe(false);
        expect(findRows()).toHaveLength(4);
      });

      it('calls Sentry with the error', () => {
        expect(Sentry.captureException).toHaveBeenCalledWith(error);
      });
    });
  });

  describe('with a capability that is off for the group', () => {
    const offForGroupProject = (flowStatus) =>
      projectWith([
        withFlowStatus(capability('SAST_FALSE_POSITIVE', true, 'AUTO'), flowStatus),
        capability('SECRET_DETECTION_FALSE_POSITIVE', true, 'MANUAL'),
        capability('SBOM_INGESTED', false),
      ]);

    it.each(['FLOW_NOT_ENABLED', 'FOUNDATIONAL_FLOWS_DISABLED'])(
      'marks the capability as off for the group when the flow status is %s',
      async (flowStatus) => {
        createComponent({ item: offForGroupProject(flowStatus) });
        showPopover();
        await waitForPromises();

        expect(findOffForGroupStatuses()).toHaveLength(1);
        expect(findOffForGroupStatuses().at(0).text()).toBe('Off for group');
        expect(findRows()[0]).toEqual(['SAST false positive detection', 'Off for group']);
      },
    );

    it.each(['AVAILABLE', 'FLOW_UNAVAILABLE', 'NOT_APPLICABLE'])(
      'renders the run mode when the flow status is %s',
      async (flowStatus) => {
        createComponent({ item: offForGroupProject(flowStatus) });
        showPopover();
        await waitForPromises();

        expect(findOffForGroupStatuses()).toHaveLength(0);
        expect(findRows()[0]).toEqual(['SAST false positive detection', 'Automatic']);
      },
    );

    it('keeps the badge enabled and hides the footer when another capability runs', async () => {
      createComponent({ item: offForGroupProject('FLOW_NOT_ENABLED') });
      showPopover();
      await waitForPromises();

      expect(findBadge().attributes('aria-label')).toBe('Automated Triage and Remediation enabled');
      expect(findOffForGroupFooter().exists()).toBe(false);
    });

    it('does not mark a disabled capability as off for the group', async () => {
      createComponent({
        item: projectWith([
          capability('SAST_FALSE_POSITIVE', true, 'AUTO'),
          withFlowStatus(capability('SBOM_INGESTED', false, 'MANUAL'), 'FLOW_NOT_ENABLED'),
        ]),
      });
      showPopover();
      await waitForPromises();

      expect(findOffForGroupStatuses()).toHaveLength(0);
    });
  });

  describe('when every enabled capability is off for the group', () => {
    const allOffProject = projectWith([
      withFlowStatus(capability('SAST_FALSE_POSITIVE', true, 'AUTO'), 'FLOW_NOT_ENABLED'),
      withFlowStatus(
        capability('SECRET_DETECTION_FALSE_POSITIVE', true, 'MANUAL'),
        'FOUNDATIONAL_FLOWS_DISABLED',
      ),
      capability('SBOM_INGESTED', false),
    ]);

    beforeEach(async () => {
      createComponent({ item: allOffProject });
      showPopover();
      await waitForPromises();
    });

    it('renders the badge as not enabled', () => {
      expect(findBadge().attributes('aria-label')).toBe(
        'Automated Triage and Remediation not enabled',
      );
      expect(findBadge().props('variant')).toBe('neutral');
    });

    it('still shows the profile and marks each enabled capability as off for the group', () => {
      expect(findProfileRow().text()).toContain('Triage and Remediation (Standard)');
      expect(findOffForGroupStatuses()).toHaveLength(2);
      expect(findDescription().exists()).toBe(false);
    });

    it('asks a group Owner to turn them on', () => {
      expect(findOffForGroupFooter().text()).toBe('Ask a group Owner to turn them on.');
      expect(findOffForGroupFooter().findComponent(GlLink).attributes('href')).toBe(
        '/groups/gitlab-org/-/group_members?max_role=static-50',
      );
      expect(findDuoSettingsLink().exists()).toBe(false);
    });

    describe('when the user can open the Duo settings', () => {
      beforeEach(async () => {
        createComponent({
          item: allOffProject,
          canAdminRootGroup: true,
          duoSettingsPath: '/groups/gitlab-org/-/settings/gitlab_duo',
        });
        showPopover();
        await waitForPromises();
      });

      it('links to the Duo settings', () => {
        expect(findDuoSettingsLink().text()).toBe('Turn them on in GitLab Duo settings');
        expect(findDuoSettingsLink().attributes('href')).toBe(
          '/groups/gitlab-org/-/settings/gitlab_duo',
        );
        expect(findOffForGroupFooter().text()).not.toContain('Ask a group Owner');
      });
    });
  });

  describe('when a scanner is not running for an enabled capability', () => {
    const capabilities = [
      capability('SAST_FALSE_POSITIVE', true, 'AUTO'),
      capability('SECRET_DETECTION_FALSE_POSITIVE', true, 'MANUAL'),
      capability('SBOM_INGESTED', false),
    ];
    const findScannerOffStatuses = () => wrapper.findAllByTestId('scanner-off-status');

    describe('with the secret detection scanner missing', () => {
      beforeEach(async () => {
        createComponent({
          item: projectWith(capabilities, [analyzerStatus('SAST')]),
        });
        showPopover();
        await waitForPromises();
      });

      it('renders the badge as needs attention', () => {
        expect(findBadge().attributes('aria-label')).toBe(
          'Automated Triage and Remediation needs attention',
        );
        expect(findBadge().props('variant')).toBe('warning');
      });

      it('marks only the capability whose scanner is off', () => {
        const rowFor = (title) => findRows().find(([name]) => name === title);

        expect(findScannerOffStatuses()).toHaveLength(1);
        expect(rowFor('Secret detection false positive detection')).toEqual([
          'Secret detection false positive detection',
          'Scanner not enabled',
        ]);
        expect(rowFor('SAST false positive detection')).toEqual([
          'SAST false positive detection',
          'Automatic',
        ]);
      });

      it('does not show the off for group footer', () => {
        expect(findOffForGroupFooter().exists()).toBe(false);
      });
    });

    it('treats a NOT_CONFIGURED analyzer as not running', () => {
      createComponent({
        item: projectWith(capabilities, [
          analyzerStatus('SAST'),
          analyzerStatus('SECRET_DETECTION', 'NOT_CONFIGURED'),
        ]),
      });

      expect(findBadge().props('variant')).toBe('warning');
    });

    it.each(['SUCCESS', 'FAILED', 'STALE'])('treats a %s analyzer as running', (status) => {
      createComponent({
        item: projectWith(capabilities, [
          analyzerStatus('SAST_ADVANCED', status),
          analyzerStatus('SECRET_DETECTION_SECRET_PUSH_PROTECTION', status),
        ]),
      });

      expect(findBadge().props('variant')).toBe('success');
    });

    it('stays enabled when the scanner of the only enabled capability runs', () => {
      createComponent({
        item: projectWith(
          [capability('SAST_FALSE_POSITIVE', true, 'AUTO')],
          [analyzerStatus('SAST')],
        ),
      });

      expect(findBadge().props('variant')).toBe('success');
    });

    it('needs attention when the analyzer statuses are missing', () => {
      createComponent({ item: { ...projectWith(capabilities), analyzerStatuses: undefined } });

      expect(findBadge().props('variant')).toBe('warning');
    });

    it('keeps the badge not enabled when every enabled capability is off for the group', () => {
      createComponent({
        item: projectWith(
          [withFlowStatus(capability('SAST_FALSE_POSITIVE', true, 'AUTO'), 'FLOW_NOT_ENABLED')],
          [],
        ),
      });

      expect(findBadge().attributes('aria-label')).toBe(
        'Automated Triage and Remediation not enabled',
      );
      expect(findBadge().props('variant')).toBe('neutral');
    });

    it('marks off for group, not scanner off, when both apply to a capability', async () => {
      createComponent({
        item: projectWith(
          [
            withFlowStatus(capability('SAST_FALSE_POSITIVE', true, 'AUTO'), 'FLOW_NOT_ENABLED'),
            capability('SECRET_DETECTION_FALSE_POSITIVE', true, 'MANUAL'),
          ],
          [analyzerStatus('SECRET_DETECTION')],
        ),
      });
      showPopover();
      await waitForPromises();

      expect(findOffForGroupStatuses()).toHaveLength(1);
      expect(findScannerOffStatuses()).toHaveLength(0);
      expect(findBadge().props('variant')).toBe('success');
    });
  });

  describe('with an enabled capability that has no run mode', () => {
    it('renders an en dash', () => {
      createComponent({ item: projectWith([capability('SBOM_INGESTED', true, null)]) });

      expect(findRows()).toContainEqual(['Dependency scanning auto-remediation', '–']);
    });
  });

  describe('when no capability is enabled', () => {
    it.each`
      description                     | item
      ${'all are disabled'}           | ${projectWith([capability('SAST_FALSE_POSITIVE', false)])}
      ${'coverage is missing'}        | ${mockProject}
      ${'only an unlisted one is on'} | ${projectWith([capability('VULNERABILITY_ENRICHMENT', true)])}
    `('renders a grey dashed badge for $description', ({ item }) => {
      createComponent({ item });

      expect(findBadge().props('variant')).toBe('neutral');
      expect(findBadge().classes()).toContain('gl-border-dashed');
      expect(findBadge().text()).toBe('Automated Triage and Remediation');
      expect(findBadge().attributes('aria-label')).toBe(
        'Automated Triage and Remediation not enabled',
      );
    });

    it('renders the description', async () => {
      createComponent();
      showPopover();
      await waitForPromises();

      expect(queryHandler).not.toHaveBeenCalled();
      expect(findProfileRow().exists()).toBe(false);
      expect(findRows()).toEqual([]);
      expect(findDescription().text()).toBe(
        "Automated Triage and Remediation isn't acting on vulnerabilities in this project. Apply a profile to turn it on.",
      );
    });

    it('emits the project from Apply profile', () => {
      createComponent();

      expect(findApplyButton().text()).toBe('Apply profile');
      expect(findChangeButton().exists()).toBe(false);

      findApplyButton().vm.$emit('click');

      expect(wrapper.emitted('open-triage-drawer')).toEqual([
        [{ project: mockProject, presetId: '' }],
      ]);
    });

    describe('without permission to apply profiles', () => {
      it('hides Apply profile', () => {
        createComponent({ canApplyProfiles: false });

        expect(findApplyButton().exists()).toBe(false);
        expect(findDescription().exists()).toBe(true);
      });
    });
  });

  describe('with hideProfileActions', () => {
    it('hides Change profile', async () => {
      createComponent({ item: enabledProject, hideProfileActions: true });
      showPopover();
      await waitForPromises();

      expect(findChangeButton().exists()).toBe(false);
      expect(findManageButton().text()).toBe('Manage configuration');
    });

    it('hides Apply profile', () => {
      createComponent({ hideProfileActions: true });

      expect(findDescription().exists()).toBe(true);
      expect(findApplyButton().exists()).toBe(false);
    });

    it('links an Owner to GitLab Duo settings', async () => {
      createComponent({
        item: projectWith([
          withFlowStatus(capability('SAST_FALSE_POSITIVE', true, 'AUTO'), 'FLOW_NOT_ENABLED'),
        ]),
        hideProfileActions: true,
        canAdminRootGroup: true,
        duoSettingsPath: '/groups/gitlab-org/-/settings/gitlab_duo',
      });
      showPopover();
      await waitForPromises();

      expect(findDuoSettingsLink().attributes('href')).toBe(
        '/groups/gitlab-org/-/settings/gitlab_duo',
      );
      expect(findOffForGroupFooter().text()).not.toContain('Ask a group Owner');
    });
  });

  describe('with an enabled capability that has no flow status', () => {
    it('renders a green badge', () => {
      createComponent({
        item: projectWith([withFlowStatus(capability('SAST_FALSE_POSITIVE', true), null)]),
      });

      expect(findBadge().props('variant')).toBe('success');
      expect(findOffForGroupStatuses()).toHaveLength(0);
    });
  });
});
