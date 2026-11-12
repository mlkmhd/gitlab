import Vue from 'vue';
import VueApollo from 'vue-apollo';
import { GlAlert, GlButton, GlIcon, GlLink, GlPopover } from '@gitlab/ui';
import { stubComponent, RENDER_ALL_SLOTS_TEMPLATE } from 'helpers/stub_component';
import { mountExtended } from 'helpers/vue_test_utils_helper';
import createMockApollo from 'helpers/mock_apollo_helper';
import waitForPromises from 'helpers/wait_for_promises';
import * as Sentry from '~/sentry/sentry_browser_wrapper';
import TriagePresetCapabilities from 'ee/security_configuration/components/scan_profiles/triage_preset_capabilities.vue';
import groupTriageAndRemediationFlowStatusesQuery from 'ee/security_configuration/graphql/scan_profiles/group_triage_and_remediation_flow_statuses.query.graphql';
import { TRIAGE_PRESET_CAPABILITY_GROUPS } from 'ee/security_configuration/constants';

Vue.use(VueApollo);

const ALL_TRIGGERS = TRIAGE_PRESET_CAPABILITY_GROUPS.flatMap((group) =>
  group.capabilities.map((capability) => capability.triggerType),
);

const presetTriggerSettings = ({
  severityLevel,
  runMode,
  dependencySeverityLevel,
  upgradePolicy,
  openMergeRequestsLimit,
}) => [
  ...[
    'SAST_FALSE_POSITIVE',
    'SAST_VULNERABILITY_RESOLUTION',
    'SECRET_DETECTION_FALSE_POSITIVE',
  ].map((triggerType) => ({ triggerType, configuration: { severityLevel, runMode } })),
  {
    triggerType: 'SBOM_INGESTED',
    configuration: {
      severityLevel: dependencySeverityLevel,
      upgradePolicy,
      openMergeRequestsLimit,
    },
  },
];

const HELP_TEXT =
  'Projects with Agentic Breaking Change Resolution turned on can also get major version upgrades.';

const flowStatusesResponse = (statuses = {}) => ({
  data: {
    group: {
      id: 'gid://gitlab/Group/1',
      triageAndRemediationFlowStatuses: ALL_TRIGGERS.map((triggerType) => ({
        triggerType,
        flowStatus: statuses[triggerType] ?? 'FLOW_ENABLED',
      })),
    },
  },
});

describe('TriagePresetCapabilities', () => {
  let wrapper;
  let flowStatusesHandler;

  const createComponent = ({
    triggers = ALL_TRIGGERS,
    triggerSettings,
    handler = jest.fn().mockResolvedValue(flowStatusesResponse()),
    duoSettingsPath = '/groups/root/-/settings/gitlab_duo',
  } = {}) => {
    flowStatusesHandler = handler;

    wrapper = mountExtended(TriagePresetCapabilities, {
      apolloProvider: createMockApollo([
        [groupTriageAndRemediationFlowStatusesQuery, flowStatusesHandler],
      ]),
      propsData: { triggers, triggerSettings },
      provide: {
        groupFullPath: 'root/subgroup',
        rootGroupName: 'Tanuki Tech',
        duoSettingsPath,
        groupOwnersPath: '/groups/root/-/group_members?max_role=static-50',
      },
      stubs: {
        GlPopover: stubComponent(GlPopover, { template: RENDER_ALL_SLOTS_TEMPLATE }),
      },
    });
  };

  const findGroups = () => wrapper.findAll('section');
  const findCapability = (triggerType) => wrapper.findByTestId(`capability-${triggerType}`);
  const findButton = (triggerType) => findCapability(triggerType).findComponent(GlButton);
  const findPopover = (triggerType) => findCapability(triggerType).findComponent(GlPopover);
  const findIcon = (triggerType) => findCapability(triggerType).findAllComponents(GlIcon).at(0);
  const findSummary = (triggerType) =>
    findCapability(triggerType).findByTestId('capability-summary');
  const findHelp = (triggerType) => findCapability(triggerType).findByTestId('capability-help');
  const findOffBadge = (triggerType) =>
    findCapability(triggerType).findByTestId('off-for-group-badge');
  const findAlert = () => wrapper.findComponent(GlAlert);
  const findAlertLines = () => wrapper.findAllByTestId('off-for-group-capability');
  const findOffPopover = (triggerType) =>
    findCapability(triggerType).findComponentByTestId('off-for-group-popover');

  beforeEach(() => {
    createComponent();
  });

  it('renders every capability under its heading', () => {
    const groups = findGroups().wrappers.map((group) => ({
      heading: group.find('h4').text(),
      capabilities: group.findAll('h5').wrappers.map((title) => title.text()),
    }));

    expect(groups).toEqual([
      {
        heading: 'SAST',
        capabilities: ['SAST false positive detection', 'SAST vulnerability resolution'],
      },
      { heading: 'Dependencies', capabilities: ['Dependency scanning auto-remediation'] },
      { heading: 'Secrets', capabilities: ['Secret detection false positive detection'] },
    ]);
  });

  it('renders an icon for each capability', () => {
    const icons = [
      'SAST_FALSE_POSITIVE',
      'SAST_VULNERABILITY_RESOLUTION',
      'SBOM_INGESTED',
      'SECRET_DETECTION_FALSE_POSITIVE',
    ].map((triggerType) => findIcon(triggerType).props('name'));

    expect(icons).toEqual(['false-positive', 'merge-request', 'package', 'key']);
  });

  it('renders the capability name in its button label', () => {
    expect(findButton('SBOM_INGESTED').attributes('aria-label')).toBe(
      'About Dependency scanning auto-remediation',
    );
  });

  it('links each popover to its own button', () => {
    const ids = ['SAST_FALSE_POSITIVE', 'SBOM_INGESTED'].map((triggerType) => {
      const id = findButton(triggerType).attributes('id');

      expect(findPopover(triggerType).props('target')).toBe(id);

      return id;
    });

    expect(ids[0]).not.toBe(ids[1]);
  });

  it.each(ALL_TRIGGERS)('shows a description of %s in its popover', (triggerType) => {
    expect(findPopover(triggerType).find('p').text()).not.toBe('');
  });

  it.each`
    triggerType                          | description                                                                   | note
    ${'SAST_FALSE_POSITIVE'}             | ${'Flags likely false positives, reviewing each SAST vulnerability.'}         | ${'Analysis is performed by AI.'}
    ${'SAST_VULNERABILITY_RESOLUTION'}   | ${'Opens a fix merge request that rewrites vulnerable code.'}                 | ${'Fixes are generated by AI.'}
    ${'SBOM_INGESTED'}                   | ${'Opens a fix merge request that updates the dependency to a safe version.'} | ${'Updates the dependency version without AI, so no credits are spent.'}
    ${'SECRET_DETECTION_FALSE_POSITIVE'} | ${'Flags likely false positives, reviewing each detected secret.'}            | ${'Analysis is performed by AI.'}
  `('shows the popover lines of $triggerType', ({ triggerType, description, note }) => {
    const lines = findPopover(triggerType)
      .findAll('p')
      .wrappers.map((line) => line.text());

    expect(lines).toEqual([description, note]);
  });

  it('shows no summary without trigger settings', () => {
    expect(findSummary('SAST_FALSE_POSITIVE').exists()).toBe(false);
  });

  describe.each`
    preset            | severityLevel | runMode     | dependencySeverityLevel | upgradePolicy | openMergeRequestsLimit | summary                           | dependencySummary                                                        | helpText
    ${'Conservative'} | ${'HIGH'}     | ${'MANUAL'} | ${'HIGH'}               | ${'MINOR'}    | ${5}                   | ${'High and above · On demand'}   | ${'High and above · Minor and patch versions · Up to 5 open MRs'}        | ${HELP_TEXT}
    ${'Standard'}     | ${'MEDIUM'}   | ${'AUTO'}   | ${'HIGH'}               | ${'MINOR'}    | ${30}                  | ${'Medium and above · Automatic'} | ${'High and above · Minor and patch versions · Up to 30 open MRs'}       | ${HELP_TEXT}
    ${'Proactive'}    | ${'INFO'}     | ${'AUTO'}   | ${'INFO'}               | ${'MAJOR'}    | ${30}                  | ${'All severities · Automatic'}   | ${'Low and above · Major, minor and patch versions · Up to 30 open MRs'} | ${null}
  `(
    'with the $preset preset',
    ({
      severityLevel,
      runMode,
      dependencySeverityLevel,
      upgradePolicy,
      openMergeRequestsLimit,
      summary,
      dependencySummary,
      helpText,
    }) => {
      beforeEach(() => {
        createComponent({
          triggerSettings: presetTriggerSettings({
            severityLevel,
            runMode,
            dependencySeverityLevel,
            upgradePolicy,
            openMergeRequestsLimit,
          }),
        });
      });

      it.each([
        'SAST_VULNERABILITY_RESOLUTION',
        'SAST_FALSE_POSITIVE',
        'SECRET_DETECTION_FALSE_POSITIVE',
      ])('shows the severity scope and run mode of %s', (triggerType) => {
        expect(findSummary(triggerType).text()).toBe(summary);
        expect(findHelp(triggerType).exists()).toBe(false);
      });

      it('shows the summary of dependency remediation', () => {
        expect(findSummary('SBOM_INGESTED').text()).toBe(dependencySummary);
      });

      it('shows the upgrade help of dependency remediation', () => {
        const help = findHelp('SBOM_INGESTED');

        expect(help.exists() ? help.text() : null).toBe(helpText);
      });
    },
  );

  it('shows an unknown dependency severity as low', () => {
    createComponent({
      triggerSettings: presetTriggerSettings({
        dependencySeverityLevel: 'UNKNOWN',
        upgradePolicy: 'MINOR',
        openMergeRequestsLimit: 5,
      }),
    });

    expect(findSummary('SBOM_INGESTED').text()).toBe(
      'Low and above · Minor and patch versions · Up to 5 open MRs',
    );
  });

  it('shows a limit of one open MR in the singular', () => {
    createComponent({
      triggerSettings: presetTriggerSettings({
        dependencySeverityLevel: 'HIGH',
        upgradePolicy: 'MINOR',
        openMergeRequestsLimit: 1,
      }),
    });

    expect(findSummary('SBOM_INGESTED').text()).toBe(
      'High and above · Minor and patch versions · Up to 1 open MR',
    );
  });

  describe('with some triggers off', () => {
    beforeEach(() => {
      createComponent({
        triggers: ['SAST_FALSE_POSITIVE', 'SECRET_DETECTION_FALSE_POSITIVE'],
      });
    });

    it('hides the capability of an off trigger', () => {
      expect(findCapability('SAST_FALSE_POSITIVE').exists()).toBe(true);
      expect(findCapability('SAST_VULNERABILITY_RESOLUTION').exists()).toBe(false);
    });

    it('hides a group with every trigger off', () => {
      expect(findGroups().wrappers.map((group) => group.find('h4').text())).toEqual([
        'SAST',
        'Secrets',
      ]);
    });
  });

  describe('flow statuses of the group', () => {
    it('fetches the flow statuses of the group', async () => {
      await waitForPromises();

      expect(flowStatusesHandler).toHaveBeenCalledWith({ fullPath: 'root/subgroup' });
    });

    describe('when every capability is on', () => {
      beforeEach(async () => {
        await waitForPromises();
      });

      it('shows no badge', () => {
        expect(wrapper.findByTestId('off-for-group-badge').exists()).toBe(false);
      });

      it('shows no alert', () => {
        expect(findAlert().exists()).toBe(false);
      });
    });

    describe('when some capabilities are off for the group', () => {
      const handler = () =>
        jest.fn().mockResolvedValue(
          flowStatusesResponse({
            SECRET_DETECTION_FALSE_POSITIVE: 'FLOW_NOT_ENABLED',
            SAST_FALSE_POSITIVE: 'FOUNDATIONAL_FLOWS_DISABLED',
            SBOM_INGESTED: 'FLOW_UNAVAILABLE',
          }),
        );

      describe('and the user can change GitLab Duo settings', () => {
        beforeEach(async () => {
          createComponent({ handler: handler() });
          await waitForPromises();
        });

        it.each`
          triggerType                          | isOff
          ${'SAST_FALSE_POSITIVE'}             | ${true}
          ${'SAST_VULNERABILITY_RESOLUTION'}   | ${false}
          ${'SBOM_INGESTED'}                   | ${false}
          ${'SECRET_DETECTION_FALSE_POSITIVE'} | ${true}
        `('shows the Off for group badge on $triggerType: $isOff', ({ triggerType, isOff }) => {
          expect(findOffBadge(triggerType).exists()).toBe(isOff);
        });

        it('shows the badge label', () => {
          expect(findOffBadge('SAST_FALSE_POSITIVE').text()).toBe('Off for group');
        });

        it('shows one info alert', () => {
          expect(findAlert().props()).toMatchObject({
            variant: 'info',
            title: "Some capabilities won't run yet",
            dismissible: false,
          });
        });

        it('links each off capability to GitLab Duo settings', () => {
          expect(findAlertLines().wrappers.map((line) => line.text())).toEqual([
            'SAST false positive detection is off for Tanuki Tech. Turn it on in GitLab Duo settings.',
            'Secret detection false positive detection is off for Tanuki Tech. Turn it on in GitLab Duo settings.',
          ]);
          expect(
            findAlertLines().wrappers.map((line) => line.findComponent(GlLink).attributes('href')),
          ).toEqual(['/groups/root/-/settings/gitlab_duo', '/groups/root/-/settings/gitlab_duo']);
        });

        it('renders each capability name in bold', () => {
          expect(findAlertLines().wrappers.map((line) => line.find('strong').text())).toEqual([
            'SAST false positive detection',
            'Secret detection false positive detection',
          ]);
        });

        it('renders the badge as a button', () => {
          expect(findOffBadge('SAST_FALSE_POSITIVE').element.tagName).toBe('BUTTON');
          expect(findOffBadge('SAST_FALSE_POSITIVE').attributes('type')).toBe('button');
        });

        it('links each Off for group popover to its own badge', () => {
          const ids = ['SAST_FALSE_POSITIVE', 'SECRET_DETECTION_FALSE_POSITIVE'].map(
            (triggerType) => {
              const id = findOffBadge(triggerType).attributes('id');

              expect(findOffPopover(triggerType).props('target')).toBe(id);

              return id;
            },
          );

          expect(ids[0]).not.toBe(ids[1]);
        });

        it('shows what Off for group means in its popover', () => {
          expect(findOffPopover('SAST_FALSE_POSITIVE').props('title')).toBe('Off for group');
          expect(findOffPopover('SAST_FALSE_POSITIVE').text()).toBe(
            "On in this profile, but turned off for Tanuki Tech, so it won't run.",
          );
        });
      });

      describe('and the user cannot change GitLab Duo settings', () => {
        beforeEach(async () => {
          createComponent({ handler: handler(), duoSettingsPath: null });
          await waitForPromises();
        });

        it('shows the ask a group Owner line', () => {
          expect(findAlertLines().at(0).text()).toBe(
            'SAST false positive detection is off for Tanuki Tech. Ask a group Owner to turn this on.',
          );
          expect(wrapper.findByTestId('duo-settings-link').exists()).toBe(false);
        });

        it('links to the group Owners path', () => {
          expect(findAlertLines().at(0).findComponent(GlLink).attributes('href')).toBe(
            '/groups/root/-/group_members?max_role=static-50',
          );
        });
      });

      it('hides an off capability the preset leaves out', async () => {
        createComponent({ handler: handler(), triggers: ['SECRET_DETECTION_FALSE_POSITIVE'] });
        await waitForPromises();

        expect(findAlertLines()).toHaveLength(1);
      });
    });

    describe('when the flow statuses fail to load', () => {
      const error = new Error('GraphQL error');

      beforeEach(async () => {
        jest.spyOn(Sentry, 'captureException');
        createComponent({ handler: jest.fn().mockRejectedValue(error) });
        await waitForPromises();
      });

      it('handles the error by reporting it', () => {
        expect(Sentry.captureException).toHaveBeenCalledWith(error);
      });

      it('shows no alert', () => {
        expect(findAlert().exists()).toBe(false);
      });
    });

    describe('when the flow statuses are null', () => {
      beforeEach(async () => {
        createComponent({
          handler: jest.fn().mockResolvedValue({
            data: {
              group: { id: 'gid://gitlab/Group/1', triageAndRemediationFlowStatuses: null },
            },
          }),
        });
        await waitForPromises();
      });

      it('shows no badge', () => {
        expect(wrapper.findByTestId('off-for-group-badge').exists()).toBe(false);
      });

      it('shows no alert', () => {
        expect(findAlert().exists()).toBe(false);
      });
    });
  });
});
