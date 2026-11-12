import { mountExtended } from 'helpers/vue_test_utils_helper';
import AutoRemediationCapabilities from 'ee/security_configuration/components/scan_profiles/auto_remediation_capabilities.vue';
import { mockTriageAndRemediationProfile } from './mock_data';

const profile = {
  ...mockTriageAndRemediationProfile,
  triggers: ['SAST_FALSE_POSITIVE', 'SAST_VULNERABILITY_RESOLUTION', 'SBOM_INGESTED'],
  triggerSettings: [
    {
      triggerType: 'SAST_FALSE_POSITIVE',
      configuration: { severityLevel: 'MEDIUM', runMode: 'AUTO' },
    },
    {
      triggerType: 'SAST_VULNERABILITY_RESOLUTION',
      configuration: { severityLevel: 'HIGH', runMode: 'MANUAL' },
    },
    {
      triggerType: 'SBOM_INGESTED',
      configuration: {
        severityLevel: 'HIGH',
        upgradePolicy: 'MINOR',
        openMergeRequestsLimit: 10,
        cooldown: 7,
      },
    },
  ],
};

const capability = (triggerType, overrides = {}) => ({
  triggerType,
  enabled: true,
  runMode: 'AUTO',
  flowStatus: 'AVAILABLE',
  ...overrides,
});

describe('AutoRemediationCapabilities', () => {
  let wrapper;

  const offForGroup = [capability('SAST_FALSE_POSITIVE', { flowStatus: 'FLOW_NOT_ENABLED' })];

  const createComponent = (props = {}, provide = {}) => {
    wrapper = mountExtended(AutoRemediationCapabilities, {
      propsData: { profile, capabilities: [], ...props },
      provide: {
        rootGroupName: 'Tanuki Tech',
        canAdminRootGroup: false,
        duoSettingsPath: '/admin/gitlab_duo/configuration',
        groupOwnersPath: '/groups/tanuki-tech/-/group_members?max_role=static-50',
        ...provide,
      },
    });
  };

  const findRows = () => wrapper.findAll('tbody tr');
  const rowCells = (row) =>
    row.findAll('td').wrappers.map((cell) => cell.text().replace(/\s+/g, ' '));
  const findNote = () => wrapper.findByTestId('off-for-group-note');
  const findDuoSettingsLink = () => wrapper.findByTestId('duo-settings-link');
  const findGroupOwnersLink = () => wrapper.findByTestId('group-owners-link');

  it('explains what the profile does in the project', () => {
    createComponent();

    expect(wrapper.text()).toContain(
      'What Standard does in this project, and whether each capability runs.',
    );
  });

  it('shows one row per capability the profile carries, in the drawer order', () => {
    createComponent();

    expect(findRows().wrappers.map((row) => rowCells(row)[0])).toEqual([
      'SAST false positive detection',
      'SAST vulnerability resolution',
      'Dependency scanning auto-remediation Beta',
    ]);
  });

  it('marks the capabilities that use AI and the ones in beta', () => {
    createComponent();

    const [falsePositive, resolution, dependencies] = findRows().wrappers;
    const find = (row, testId) => row.find(`[data-testid="${testId}"]`);

    expect(find(falsePositive, 'capability-ai-icon').exists()).toBe(true);
    expect(find(resolution, 'capability-ai-icon').exists()).toBe(true);
    expect(find(dependencies, 'capability-ai-icon').exists()).toBe(false);
    expect(find(falsePositive, 'capability-beta-badge').exists()).toBe(false);
    expect(find(dependencies, 'capability-beta-badge').text()).toBe('Beta');
  });

  it('shows the status and run mode of each capability', () => {
    createComponent({
      capabilities: [
        capability('SAST_FALSE_POSITIVE'),
        capability('SAST_VULNERABILITY_RESOLUTION', { runMode: 'MANUAL' }),
        capability('SBOM_INGESTED', { enabled: false, runMode: null }),
      ],
    });

    expect(findRows().wrappers.map((row) => [rowCells(row)[1], rowCells(row)[3]])).toEqual([
      ['Active', 'Automatic'],
      ['Active', 'On demand'],
      ['Off', '–'],
    ]);
  });

  it('shows the configuration run mode', () => {
    createComponent({
      capabilities: [capability('SAST_VULNERABILITY_RESOLUTION', { runMode: 'AUTO' })],
    });

    expect(rowCells(findRows().at(1))[3]).toBe('On demand');
  });

  it('shows no run mode for an off capability', () => {
    createComponent({
      capabilities: [capability('SAST_VULNERABILITY_RESOLUTION', { enabled: false })],
    });

    expect(rowCells(findRows().at(1))[3]).toBe('–');
  });

  it('shows the severity and limits of each capability', () => {
    createComponent();

    expect(findRows().wrappers.map((row) => [rowCells(row)[2], rowCells(row)[4]])).toEqual([
      ['Medium and above', '–'],
      ['High and above', '–'],
      ['High and above', 'Up to 10 open MRs, Minor and patch versions, 7-day cooldown'],
    ]);
  });

  it('shows a singular open MR limit', () => {
    createComponent({
      profile: {
        ...profile,
        triggerSettings: [
          {
            triggerType: 'SBOM_INGESTED',
            configuration: { severityLevel: 'HIGH', openMergeRequestsLimit: 1 },
          },
        ],
      },
    });

    expect(rowCells(findRows().at(2))[4]).toBe('Up to 1 open MR');
  });

  it('shows no limits and no severity when the configuration is empty or missing', () => {
    createComponent({
      profile: {
        ...profile,
        triggerSettings: [
          {
            triggerType: 'SBOM_INGESTED',
            configuration: { severityLevel: null, openMergeRequestsLimit: null, cooldown: 0 },
          },
        ],
      },
    });

    expect(findRows().wrappers.map((row) => [rowCells(row)[2], rowCells(row)[4]])).toEqual([
      ['–', '–'],
      ['–', '–'],
      ['–', '–'],
    ]);
  });

  it('shows dependency auto-remediation severity without the unknown and info levels', () => {
    createComponent({
      profile: {
        ...profile,
        triggerSettings: [
          { triggerType: 'SBOM_INGESTED', configuration: { severityLevel: 'INFO' } },
        ],
      },
    });

    expect(rowCells(findRows().at(2))[2]).toBe('Low and above');
  });

  it('keeps the configuration of a capability that is off for the group', () => {
    createComponent({
      capabilities: [capability('SBOM_INGESTED', { flowStatus: 'FLOW_NOT_ENABLED' })],
    });

    expect(rowCells(findRows().at(2)).slice(1)).toEqual([
      'Off for group',
      'High and above',
      '–',
      'Up to 10 open MRs, Minor and patch versions, 7-day cooldown',
    ]);
  });

  it('marks a capability that is off for the group, and explains it', () => {
    createComponent({
      capabilities: [
        capability('SAST_FALSE_POSITIVE', { flowStatus: 'FLOW_NOT_ENABLED' }),
        capability('SAST_VULNERABILITY_RESOLUTION', { flowStatus: 'FOUNDATIONAL_FLOWS_DISABLED' }),
        capability('SBOM_INGESTED'),
      ],
    });

    expect(rowCells(findRows().at(0))[1]).toBe('Off for group');
    expect(rowCells(findRows().at(1))[1]).toBe('Off for group');
    expect(rowCells(findRows().at(2))[1]).toBe('Active');
    expect(findNote().text()).toContain(
      "Capabilities an Owner turned off for Tanuki Tech don't run, and a profile doesn't turn them back on.",
    );
  });

  describe('the off-for-group note link', () => {
    it('asks a user who is not an Owner to contact a group Owner', () => {
      createComponent({ capabilities: offForGroup });

      expect(findNote().text()).toContain('Ask a group Owner to turn them on.');
      expect(findGroupOwnersLink().text()).toBe('group Owner');
      expect(findGroupOwnersLink().attributes('href')).toBe(
        '/groups/tanuki-tech/-/group_members?max_role=static-50',
      );
      expect(findDuoSettingsLink().exists()).toBe(false);
    });

    it('offers to turn the capabilities on to an Owner', () => {
      createComponent({ capabilities: offForGroup }, { canAdminRootGroup: true });

      expect(findDuoSettingsLink().text()).toBe('Turn them on in GitLab Duo settings');
      expect(findDuoSettingsLink().attributes('href')).toBe('/admin/gitlab_duo/configuration');
    });

    it('shows the note without a link when an Owner has no settings path', () => {
      createComponent(
        { capabilities: offForGroup },
        { canAdminRootGroup: true, duoSettingsPath: '' },
      );

      expect(findNote().exists()).toBe(true);
      expect(findDuoSettingsLink().exists()).toBe(false);
      expect(findGroupOwnersLink().exists()).toBe(false);
    });
  });

  it('marks a capability whose flow is unavailable', () => {
    createComponent({
      capabilities: [capability('SAST_FALSE_POSITIVE', { flowStatus: 'FLOW_UNAVAILABLE' })],
    });

    expect(rowCells(findRows().at(0))[1]).toBe('Unavailable');
    expect(findNote().exists()).toBe(false);
  });

  it('shows no note when nothing is off for the group', () => {
    createComponent({ capabilities: [capability('SAST_FALSE_POSITIVE')] });

    expect(findNote().exists()).toBe(false);
  });

  it('shows every capability as off before the coverage is known', () => {
    createComponent();

    expect(findRows().wrappers.map((row) => rowCells(row)[1])).toEqual(['Off', 'Off', 'Off']);
  });
});
