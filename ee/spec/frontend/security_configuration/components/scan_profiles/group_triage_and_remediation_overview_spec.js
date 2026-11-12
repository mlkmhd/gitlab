import Vue, { nextTick } from 'vue';
import VueApollo from 'vue-apollo';
import { GlButton, GlEmptyState, GlLink, GlSkeletonLoader, GlTable } from '@gitlab/ui';
import { mountExtended } from 'helpers/vue_test_utils_helper';
import createMockApollo from 'helpers/mock_apollo_helper';
import waitForPromises from 'helpers/wait_for_promises';
import { createAlert } from '~/alert';
import GroupTriageAndRemediationOverview from 'ee/security_configuration/components/scan_profiles/group_triage_and_remediation_overview.vue';
import StatisticsCardRow from 'ee/security_configuration/components/scan_profiles/statistics_card_row.vue';
import TriageProfileDrawer from 'ee/security_configuration/components/scan_profiles/triage_profile_drawer.vue';
import { ROUTE_ENABLE_TRIAGE_AND_REMEDIATION } from 'ee/security_configuration/components/enable_scanners_wizard/constants';
import SegmentedBar from 'ee/security_inventory/components/segmented_bar.vue';
import groupAvailableSecurityScanProfilesQuery from 'ee/security_configuration/graphql/scan_profiles/group_available_security_scan_profiles.query.graphql';
import groupSecurityPostureCountersQuery from 'ee/security_configuration/graphql/scan_profiles/group_security_posture_counters.query.graphql';
import groupTriageAndRemediationFlowStatusesQuery from 'ee/security_configuration/graphql/scan_profiles/group_triage_and_remediation_flow_statuses.query.graphql';
import { mockGroupUserPermissions, mockScanner, mockSecurityPostureCounters } from './mock_data';

Vue.use(VueApollo);

jest.mock('~/alert');

const GROUP_FULL_PATH = 'my-group';
const SECURITY_INVENTORY_PATH = '/groups/my-group/-/security/inventory';
const DUO_SETTINGS_PATH = '/groups/my-group/-/settings/gitlab_duo';
const GROUP_OWNERS_PATH = '/groups/my-group/-/group_members?sort=access_level_desc';

const buildFlowStatus = (triggerType, flowStatus) => ({
  triggerType,
  flowStatus,
  __typename: 'TriageAndRemediationFlowStatus',
});

const allFlowsOn = [
  buildFlowStatus('VULNERABILITY_ENRICHMENT', 'AVAILABLE'),
  buildFlowStatus('SAST_VULNERABILITY_RESOLUTION', 'AVAILABLE'),
  buildFlowStatus('SAST_FALSE_POSITIVE', 'AVAILABLE'),
  buildFlowStatus('SECRET_DETECTION_FALSE_POSITIVE', 'AVAILABLE'),
];

const TRIAGE_CONFIGURATION_TYPES = {
  VULNERABILITY_ENRICHMENT: 'VulnerabilityEnrichmentConfiguration',
  SAST_VULNERABILITY_RESOLUTION: 'SastVulnerabilityResolutionConfiguration',
  SAST_FALSE_POSITIVE: 'SastFalsePositiveConfiguration',
  SECRET_DETECTION_FALSE_POSITIVE: 'SecretDetectionFalsePositiveConfiguration',
};

const buildTriggerSetting = (triggerType, { severityLevel, runMode }) => ({
  triggerType,
  configuration: {
    severityLevel,
    runMode,
    __typename: TRIAGE_CONFIGURATION_TYPES[triggerType],
  },
  __typename: 'ScanProfileTriggerSetting',
});

const sbomTriggerSetting = {
  triggerType: 'SBOM_INGESTED',
  configuration: {
    severityLevel: null,
    upgradePolicy: 'PATCH',
    openMergeRequestsLimit: 10,
    cooldown: null,
    __typename: 'AutoRemediationConfiguration',
  },
  __typename: 'ScanProfileTriggerSetting',
};

const buildPreset = (preset, name, { settings, projectCount }) => {
  const triageSettings = Object.keys(TRIAGE_CONFIGURATION_TYPES).map((triggerType, index) =>
    buildTriggerSetting(triggerType, settings[index]),
  );

  return {
    id: `gid://gitlab/Security::ScanProfile/triage_and_remediation_${preset}`,
    name,
    description: `The ${preset} preset`,
    scanType: 'TRIAGE_AND_REMEDIATION',
    gitlabRecommended: true,
    triggers: [...Object.keys(TRIAGE_CONFIGURATION_TYPES), 'SBOM_INGESTED'],
    triggerSettings: [...triageSettings, sbomTriggerSetting],
    projectCount,
    __typename: 'ScanProfileType',
  };
};

const high = (runMode) => ({ severityLevel: 'HIGH', runMode });

const conservative = buildPreset('conservative', 'Triage and Remediation (Conservative)', {
  settings: [high('AUTO'), high('MANUAL'), high('MANUAL'), high('MANUAL')],
  projectCount: 0,
});
const standard = buildPreset('standard', 'Triage and Remediation (Standard)', {
  settings: [
    high('AUTO'),
    { severityLevel: 'MEDIUM', runMode: 'AUTO' },
    { severityLevel: 'MEDIUM', runMode: 'AUTO' },
    { severityLevel: 'MEDIUM', runMode: 'AUTO' },
  ],
  projectCount: 1,
});
const proactive = buildPreset('proactive', 'Triage and Remediation (Proactive)', {
  settings: Array(4).fill({ severityLevel: 'INFO', runMode: 'AUTO' }),
  projectCount: 3,
});

describe('GroupTriageAndRemediationOverview', () => {
  let wrapper;
  let presetsResolver;
  let postureCountersResolver;
  let flowStatusesResolver;

  const createPresetsResolver = (profiles = [conservative, mockScanner, standard, proactive]) =>
    jest.fn().mockResolvedValue({
      data: {
        group: {
          id: 'gid://gitlab/Group/1',
          name: GROUP_FULL_PATH,
          userPermissions: mockGroupUserPermissions,
          availableSecurityScanProfiles: profiles,
          __typename: 'Group',
        },
      },
    });

  const createPostureCountersResolver = (counters = mockSecurityPostureCounters) =>
    jest.fn().mockResolvedValue({
      data: {
        group: {
          id: 'gid://gitlab/Group/1',
          webPath: '/groups/my-group',
          securityPostureCounters: counters,
          __typename: 'Group',
        },
      },
    });

  const createFlowStatusesResolver = (flowStatuses = allFlowsOn) =>
    jest.fn().mockResolvedValue({
      data: {
        group: {
          id: 'gid://gitlab/Group/1',
          triageAndRemediationFlowStatuses: flowStatuses,
          __typename: 'Group',
        },
      },
    });

  const createComponent = ({
    queryResolver = createPresetsResolver(),
    countersResolver = createPostureCountersResolver(),
    flowsResolver = createFlowStatusesResolver(),
    groupFullPath = GROUP_FULL_PATH,
    duoSettingsPath = DUO_SETTINGS_PATH,
    canApplyProfiles = true,
  } = {}) => {
    presetsResolver = queryResolver;
    postureCountersResolver = countersResolver;
    flowStatusesResolver = flowsResolver;

    wrapper = mountExtended(GroupTriageAndRemediationOverview, {
      apolloProvider: createMockApollo([
        [groupAvailableSecurityScanProfilesQuery, presetsResolver],
        [groupSecurityPostureCountersQuery, postureCountersResolver],
        [groupTriageAndRemediationFlowStatusesQuery, flowStatusesResolver],
      ]),
      provide: {
        groupFullPath,
        securityInventoryPath: SECURITY_INVENTORY_PATH,
        duoSettingsPath,
        groupOwnersPath: GROUP_OWNERS_PATH,
        canApplyProfiles,
      },
      stubs: { TriageProfileDrawer: true },
    });
  };

  const findTable = () => wrapper.findComponent(GlTable);
  const findProfileNames = () => wrapper.findAllByTestId('profile-name');
  const findSummaries = () => wrapper.findAllByTestId('profile-summary');
  const findCoveragePercentages = () => wrapper.findAllByTestId('coverage-percentage');
  const findCoverageDetails = () => wrapper.findAllByTestId('coverage-details');
  const findSegmentedBars = () => wrapper.findAllComponents(SegmentedBar);
  const findViewDetailsButtons = () =>
    wrapper.findAllComponents('[data-testid="view-details-button"]');
  const findDrawer = () => wrapper.findComponent(TriageProfileDrawer);
  const findEmptyState = () => wrapper.findComponent(GlEmptyState);
  const findStatisticsCardRow = () => wrapper.findComponent(StatisticsCardRow);
  const findApplyProfileButton = () => wrapper.findComponentByTestId('apply-profile-button');
  const findDescription = () => wrapper.findByTestId('triage-and-remediation-description');
  const findGetStartedButton = () =>
    wrapper.findComponentByTestId('triage-and-remediation-get-started-button');
  const findCard = (title) =>
    findStatisticsCardRow()
      .props('cards')
      .find((card) => card.title === title);

  describe('while loading', () => {
    beforeEach(() => {
      createComponent();
    });

    it('renders the table as busy', () => {
      expect(findTable().attributes('aria-busy')).toBe('true');
    });

    it('renders the stat cards as loading', () => {
      expect(findStatisticsCardRow().props('loading')).toBe(true);
    });

    it('does not render the "Apply profile" button', () => {
      expect(findApplyProfileButton().exists()).toBe(false);
    });
  });

  describe('when the presets load on a top-level group', () => {
    beforeEach(async () => {
      createComponent();
      await waitForPromises();
    });

    it('fetches the recommended profiles of the group', () => {
      expect(presetsResolver).toHaveBeenCalledWith({
        fullPath: GROUP_FULL_PATH,
        gitlabRecommended: true,
      });
    });

    it('renders Standard first, then by project count', () => {
      expect(findProfileNames().wrappers.map((name) => name.text())).toEqual([
        'Triage and Remediation (Standard)',
        'Triage and Remediation (Proactive)',
        'Triage and Remediation (Conservative)',
      ]);
    });

    it('renders lowest severity and capability count', () => {
      expect(findSummaries().wrappers.map((summary) => summary.text())).toEqual([
        'Medium severity and above · 4 capabilities',
        'All severities · 4 capabilities',
        'High severity and above · 4 capabilities',
      ]);
    });

    it('does not show the empty state', () => {
      expect(findEmptyState().exists()).toBe(false);
    });

    it('links "Apply profile" to the wizard', () => {
      expect(findApplyProfileButton().props('to')).toStrictEqual({
        name: ROUTE_ENABLE_TRIAGE_AND_REMEDIATION,
      });
    });

    it('fetches the flow statuses of the group', () => {
      expect(flowStatusesResolver).toHaveBeenCalledWith({ fullPath: GROUP_FULL_PATH });
    });

    it('renders the stat cards loaded', () => {
      expect(findStatisticsCardRow().props('loading')).toBe(false);
    });

    it('renders the projects without a profile card', () => {
      expect(findCard('Projects without a profile')).toEqual({
        title: 'Projects without a profile',
        value: 6,
        description: 'Have no Automated Triage and Remediation profile',
        linkText: 'View in Security inventory',
        href: SECURITY_INVENTORY_PATH,
      });
    });

    it('renders the capabilities card with none off', () => {
      expect(findCard('Capabilities off for group')).toEqual({
        title: 'Capabilities off for group',
        info: "Off for group, so they don't run on any project until turned on",
        value: '—',
        items: ['None'],
        description: 'Every capability can run',
        linkText: 'GitLab Duo settings',
        href: DUO_SETTINGS_PATH,
      });
    });

    it('renders the coverage columns', () => {
      expect(
        findTable()
          .props('fields')
          .map(({ key }) => key),
      ).toEqual(['profile', 'coverage', 'actions']);
    });

    it('renders the share of projects covered', () => {
      expect(findCoveragePercentages().wrappers.map((cell) => cell.text())).toEqual([
        '10%',
        '30%',
        '0%',
      ]);
    });

    it('renders covered and uncovered bar segments', () => {
      expect(findSegmentedBars().at(1).props('segments')).toEqual([
        { class: 'gl-bg-green-500', count: 3 },
        { class: 'gl-bg-status-neutral', count: 7 },
      ]);
    });

    it('renders an amber bar for on-demand capabilities', () => {
      expect(findSegmentedBars().at(2).props('segments')[0].class).toBe('gl-bg-orange-200');
    });

    it('renders the project count and the run mode', () => {
      expect(findCoverageDetails().wrappers.map((cell) => cell.text())).toEqual([
        '1 project · All capabilities automatic',
        '3 projects · All capabilities automatic',
        'Not applied · 3 of 4 capabilities on demand',
      ]);
    });

    it('renders "View details" on each preset', () => {
      expect(findViewDetailsButtons().wrappers.map((button) => button.text())).toEqual([
        'View details',
        'View details',
        'View details',
      ]);
    });

    it('renders the drawer closed', () => {
      expect(findDrawer().props()).toMatchObject({ open: false, presetId: '', project: null });
    });

    describe('when "View details" is clicked', () => {
      beforeEach(async () => {
        findViewDetailsButtons().at(1).vm.$emit('click');
        await nextTick();
      });

      it('passes the clicked preset and no project', () => {
        expect(findDrawer().props()).toMatchObject({
          open: true,
          presetId: proactive.id,
          project: null,
        });
      });

      describe('and the drawer emits close', () => {
        beforeEach(async () => {
          findDrawer().vm.$emit('close');
          await nextTick();
        });

        it('hides the drawer', () => {
          expect(findDrawer().props('open')).toBe(false);
        });
      });
    });
  });

  describe('with every capability on demand at critical severity', () => {
    const triageTriggers = Object.keys(TRIAGE_CONFIGURATION_TYPES);
    const criticalOnly = {
      ...standard,
      triggers: triageTriggers,
      triggerSettings: triageTriggers.map((triggerType) =>
        buildTriggerSetting(triggerType, { severityLevel: 'CRITICAL', runMode: 'MANUAL' }),
      ),
    };

    beforeEach(async () => {
      createComponent({ queryResolver: createPresetsResolver([criticalOnly]) });
      await waitForPromises();
    });

    it('renders the critical severity summary', () => {
      expect(findSummaries().at(0).text()).toBe('Critical severity only · 3 capabilities');
    });

    it('renders every capability as on demand', () => {
      expect(findCoverageDetails().at(0).text()).toBe('1 project · All capabilities on demand');
    });
  });

  describe('with only vulnerability enrichment on demand at low severity', () => {
    const enrichmentOnDemand = buildPreset('enrichment', 'Enrichment on demand', {
      settings: [
        { severityLevel: 'LOW', runMode: 'MANUAL' },
        ...Array(3).fill({ severityLevel: 'MEDIUM', runMode: 'AUTO' }),
      ],
      projectCount: 1,
    });

    beforeEach(async () => {
      createComponent({ queryResolver: createPresetsResolver([enrichmentOnDemand]) });
      await waitForPromises();
    });

    it('renders the severity and count without enrichment', () => {
      expect(findSummaries().at(0).text()).toBe('Medium severity and above · 4 capabilities');
    });

    it('renders every capability as automatic', () => {
      expect(findCoverageDetails().at(0).text()).toBe('1 project · All capabilities automatic');
    });

    it('renders a green bar', () => {
      expect(findSegmentedBars().at(0).props('segments')[0].class).toBe('gl-bg-green-500');
    });
  });

  describe('with no severity on any capability', () => {
    const sbomOnly = {
      ...standard,
      triggers: ['SBOM_INGESTED'],
      triggerSettings: [sbomTriggerSetting],
    };

    beforeEach(async () => {
      createComponent({ queryResolver: createPresetsResolver([sbomOnly]) });
      await waitForPromises();
    });

    it('renders the capability count as the summary', () => {
      expect(findSummaries().at(0).text()).toBe('1 capability');
    });
  });

  describe('while the project counts load', () => {
    beforeEach(async () => {
      createComponent({ countersResolver: jest.fn().mockReturnValue(new Promise(() => {})) });
      await waitForPromises();
    });

    it('renders a skeleton loader in each coverage cell', () => {
      expect(findTable().findAllComponents(GlSkeletonLoader)).toHaveLength(3);
    });

    it('does not render the bars', () => {
      expect(findSegmentedBars()).toHaveLength(0);
    });
  });

  describe('while the flow statuses load', () => {
    beforeEach(async () => {
      createComponent({ flowsResolver: jest.fn().mockReturnValue(new Promise(() => {})) });
      await waitForPromises();
    });

    it('renders the stat cards as loading', () => {
      expect(findStatisticsCardRow().props('loading')).toBe(true);
    });
  });

  describe('on a subgroup', () => {
    beforeEach(async () => {
      createComponent({ groupFullPath: `${GROUP_FULL_PATH}/subgroup` });
      await waitForPromises();
    });

    it('hides the coverage column', () => {
      expect(
        findTable()
          .props('fields')
          .map(({ key }) => key),
      ).toEqual(['profile', 'actions']);
    });
  });

  describe('when no project in the group has a triage and remediation profile', () => {
    beforeEach(async () => {
      createComponent({
        countersResolver: createPostureCountersResolver({
          ...mockSecurityPostureCounters,
          withTriageCoverage: 0,
        }),
      });
      await waitForPromises();
    });

    it('renders the empty state', () => {
      expect(findEmptyState().props('title')).toBe('Stop triaging vulnerabilities by hand');
      expect(findEmptyState().findComponent(GlButton).text()).toBe('Get started');
    });

    it('links "Get started" to the wizard', () => {
      expect(findEmptyState().findComponent(GlButton).props('to')).toStrictEqual({
        name: ROUTE_ENABLE_TRIAGE_AND_REMEDIATION,
      });
    });

    it('does not render the table', () => {
      expect(findTable().exists()).toBe(false);
    });
  });

  describe('without permission to apply profiles', () => {
    it('renders the description', async () => {
      createComponent({ canApplyProfiles: false });
      await waitForPromises();

      expect(findDescription().exists()).toBe(true);
    });

    it('does not render the "Apply profile" button', async () => {
      createComponent({ canApplyProfiles: false });
      await waitForPromises();

      expect(findApplyProfileButton().exists()).toBe(false);
    });

    it('does not render the "Get started" button', async () => {
      createComponent({
        canApplyProfiles: false,
        countersResolver: createPostureCountersResolver({
          ...mockSecurityPostureCounters,
          withTriageCoverage: 0,
        }),
      });
      await waitForPromises();

      expect(findGetStartedButton().exists()).toBe(false);
    });
  });

  describe('when the project counts fail to load', () => {
    beforeEach(async () => {
      createComponent({ countersResolver: jest.fn().mockRejectedValue(new Error('failed')) });
      await waitForPromises();
    });

    it('shows a coverage alert', () => {
      expect(createAlert).toHaveBeenCalledWith({ message: 'Failed to load project coverage.' });
    });

    it('renders a dash in place of each share', () => {
      expect(findCoveragePercentages().wrappers.map((cell) => cell.text())).toEqual([
        '—',
        '—',
        '—',
      ]);
    });

    it('renders empty bars', () => {
      expect(findSegmentedBars().at(1).props('segments')).toEqual([]);
    });

    it('keeps the project count', () => {
      expect(findCoverageDetails().at(1).text()).toBe('3 projects · All capabilities automatic');
    });

    it('renders a dash on the projects card', () => {
      expect(findCard('Projects without a profile').value).toBe('—');
    });

    it('hides the projects card description', () => {
      expect(findCard('Projects without a profile').description).toBeNull();
    });

    it('keeps the capabilities list', () => {
      expect(findCard('Capabilities off for group').items).toEqual(['None']);
    });

    it('keeps the capabilities card description', () => {
      expect(findCard('Capabilities off for group').description).toBe('Every capability can run');
    });
  });

  describe('when capabilities are off for the group', () => {
    const createOffComponent = async (options = {}) => {
      createComponent({
        flowsResolver: createFlowStatusesResolver([
          buildFlowStatus('VULNERABILITY_ENRICHMENT', 'FLOW_NOT_ENABLED'),
          buildFlowStatus('SECRET_DETECTION_FALSE_POSITIVE', 'FLOW_NOT_ENABLED'),
          buildFlowStatus('SAST_FALSE_POSITIVE', 'FLOW_UNAVAILABLE'),
          buildFlowStatus('SAST_VULNERABILITY_RESOLUTION', 'FOUNDATIONAL_FLOWS_DISABLED'),
        ]),
        ...options,
      });
      await waitForPromises();
    };

    it('renders off capabilities in capability order', async () => {
      await createOffComponent();

      expect(findCard('Capabilities off for group')).toMatchObject({
        items: ['SAST vulnerability resolution', 'Secret detection false positive detection'],
        description: null,
      });
    });

    it('renders the GitLab Duo settings link', async () => {
      await createOffComponent();

      expect(findCard('Capabilities off for group')).toMatchObject({
        linkText: 'GitLab Duo settings',
        href: DUO_SETTINGS_PATH,
      });
      expect(wrapper.findByTestId('card-message-link').exists()).toBe(false);
    });

    describe('without access to GitLab Duo settings', () => {
      it('renders the group Owner sentence and link', async () => {
        await createOffComponent({ duoSettingsPath: null });
        const link = wrapper.findByTestId('card-message-link');

        expect(findStatisticsCardRow().text()).toContain('Ask a group Owner to turn them on.');
        expect(link.text()).toBe('group Owner');
        expect(link.attributes('href')).toBe(GROUP_OWNERS_PATH);
      });
    });
  });

  describe('when the backend returns no flow statuses', () => {
    beforeEach(async () => {
      createComponent({ flowsResolver: createFlowStatusesResolver(null) });
      await waitForPromises();
    });

    it('renders a dash on the capabilities card', () => {
      expect(findCard('Capabilities off for group')).toMatchObject({
        value: '—',
        items: null,
        description: null,
      });
    });
  });

  describe('when the flow statuses fail to load', () => {
    beforeEach(async () => {
      createComponent({ flowsResolver: jest.fn().mockRejectedValue(new Error('failed')) });
      await waitForPromises();
    });

    it('shows an alert', () => {
      expect(createAlert).toHaveBeenCalledWith({
        message: 'Failed to load capability statuses.',
      });
    });

    it('renders a dash on the capabilities card', () => {
      expect(findCard('Capabilities off for group')).toMatchObject({ value: '—', items: null });
    });

    it('hides the capabilities card description', () => {
      expect(findCard('Capabilities off for group').description).toBeNull();
    });

    it('keeps the projects count', () => {
      expect(findCard('Projects without a profile').value).toBe(6);
    });

    it('keeps the projects card description', () => {
      expect(findCard('Projects without a profile').description).toBe(
        'Have no Automated Triage and Remediation profile',
      );
    });
  });

  describe('without access to GitLab Duo settings and none off', () => {
    beforeEach(async () => {
      createComponent({ duoSettingsPath: null });
      await waitForPromises();
    });

    it('renders no link on the capabilities card', () => {
      expect(
        findStatisticsCardRow()
          .findAllComponents(GlLink)
          .wrappers.map((link) => link.text()),
      ).toEqual(['View in Security inventory']);
    });
  });

  describe('when the presets fail to load', () => {
    beforeEach(async () => {
      createComponent({ queryResolver: jest.fn().mockRejectedValue(new Error('failed')) });
      await waitForPromises();
    });

    it('shows an alert', () => {
      expect(createAlert).toHaveBeenCalledWith({
        message: 'Failed to load triage and remediation profiles.',
      });
    });
  });

  describe('the description', () => {
    it('renders the description', async () => {
      createComponent();
      await waitForPromises();

      expect(findDescription().text()).toBe(
        'Open fix merge requests, flag likely false positives, and add context to new findings across your projects. To see capabilities by project, visit the Security inventory.',
      );
    });

    it('links to the security inventory', async () => {
      createComponent();
      await waitForPromises();

      expect(findDescription().findComponent(GlLink).attributes('href')).toBe(
        SECURITY_INVENTORY_PATH,
      );
    });
  });
});
