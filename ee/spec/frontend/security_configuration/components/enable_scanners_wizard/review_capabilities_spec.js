import Vue from 'vue';
import VueApollo from 'vue-apollo';
import { GlAlert, GlBadge, GlCard, GlLink, GlLoadingIcon, GlSprintf } from '@gitlab/ui';
import { shallowMountExtended } from 'helpers/vue_test_utils_helper';
import createMockApollo from 'helpers/mock_apollo_helper';
import waitForPromises from 'helpers/wait_for_promises';
import * as Sentry from '~/sentry/sentry_browser_wrapper';
import ReviewCapabilities from 'ee/security_configuration/components/enable_scanners_wizard/review_capabilities.vue';
import groupTriageAndRemediationFlowStatusesQuery from 'ee/security_configuration/graphql/scan_profiles/group_triage_and_remediation_flow_statuses.query.graphql';
import { standardPreset } from './mock_data';

Vue.use(VueApollo);

describe('EnableScannersReviewCapabilities', () => {
  let wrapper;
  let flowStatusesHandler;

  const flowStatusesResponse = (statuses) => ({
    data: {
      group: {
        __typename: 'Group',
        id: 'gid://gitlab/Group/1',
        triageAndRemediationFlowStatuses: Object.entries(statuses).map(
          ([triggerType, flowStatus]) => ({
            __typename: 'TriageAndRemediationTriggerFlowStatus',
            triggerType,
            flowStatus,
          }),
        ),
      },
    },
  });

  const allAvailable = {
    SAST_FALSE_POSITIVE: 'AVAILABLE',
    SAST_VULNERABILITY_RESOLUTION: 'AVAILABLE',
    SBOM_INGESTED: 'AVAILABLE',
    SECRET_DETECTION_FALSE_POSITIVE: 'AVAILABLE',
  };

  const preset = {
    ...standardPreset,
    triggers: ['SAST_FALSE_POSITIVE', 'SBOM_INGESTED', 'SECRET_DETECTION_FALSE_POSITIVE'],
  };

  const createComponent = ({
    statuses = allAvailable,
    handler = jest.fn().mockResolvedValue(flowStatusesResponse(statuses)),
    duoSettingsPath = null,
    groupOwnersPath = null,
  } = {}) => {
    flowStatusesHandler = handler;

    wrapper = shallowMountExtended(ReviewCapabilities, {
      apolloProvider: createMockApollo([
        [groupTriageAndRemediationFlowStatusesQuery, flowStatusesHandler],
      ]),
      provide: {
        groupFullPath: 'group/subgroup',
        rootGroupName: 'Root group',
        duoSettingsPath,
        groupOwnersPath,
        wizard: { selectedProfiles: [preset] },
      },
      stubs: { GlAlert, GlCard, GlSprintf },
    });
  };

  const findAlert = () => wrapper.findComponent(GlAlert);
  const findOffCard = () => wrapper.findByTestId('off-capabilities-card');
  const findReadyCard = () => wrapper.findByTestId('ready-capabilities-card');
  const findOffCapabilities = () => wrapper.findAllByTestId('off-capability');
  const findReadyCapabilities = () => wrapper.findAllByTestId('ready-capability');
  const findCount = (card) => card.find('[data-testid="capability-count"]').text();
  const findTitles = (rows) => rows.wrappers.map((row) => row.find('strong').text());

  it('shows a loading icon while the flow statuses load', () => {
    createComponent();

    expect(wrapper.findComponent(GlLoadingIcon).exists()).toBe(true);
  });

  it('reads the flow statuses for the group', async () => {
    createComponent();
    await waitForPromises();

    expect(flowStatusesHandler).toHaveBeenCalledWith({ fullPath: 'group/subgroup' });
  });

  describe('when every capability in the preset can run', () => {
    beforeEach(async () => {
      createComponent({
        statuses: { ...allAvailable, SAST_VULNERABILITY_RESOLUTION: 'FLOW_NOT_ENABLED' },
      });
      await waitForPromises();
    });

    it("hides the Won't run yet card", () => {
      expect(findOffCard().exists()).toBe(false);
    });

    it('shows each preset capability as ready', () => {
      expect(findCount(findReadyCard())).toBe('3 capabilities');
      expect(findTitles(findReadyCapabilities())).toEqual([
        'SAST false positive detection',
        'Dependency scanning auto-remediation',
        'Secret detection false positive detection',
      ]);
      expect(
        findReadyCapabilities().wrappers.map((row) => row.findComponent(GlBadge).text()),
      ).toEqual(['No action needed', 'No action needed', 'No action needed']);
    });
  });

  describe('when capabilities in the preset are off for the group', () => {
    const statuses = {
      SAST_FALSE_POSITIVE: 'FLOW_NOT_ENABLED',
      SAST_VULNERABILITY_RESOLUTION: 'FLOW_NOT_ENABLED',
      SBOM_INGESTED: 'FOUNDATIONAL_FLOWS_DISABLED',
      SECRET_DETECTION_FALSE_POSITIVE: 'FLOW_UNAVAILABLE',
    };

    it("shows them in the Won't run yet card", async () => {
      createComponent({ statuses });
      await waitForPromises();

      expect(findOffCard().text()).toContain("Won't run yet");
      expect(findCount(findOffCard())).toBe('2 capabilities');
      expect(findTitles(findOffCapabilities())).toEqual([
        'SAST false positive detection',
        'Dependency scanning auto-remediation',
      ]);
    });

    it('hides the Ready card', async () => {
      createComponent({ statuses });
      await waitForPromises();

      expect(findReadyCard().exists()).toBe(false);
    });

    describe('for a user who can change GitLab Duo settings', () => {
      it('links to GitLab Duo settings in the card footer', async () => {
        createComponent({ statuses, duoSettingsPath: '/groups/root/-/settings/gitlab_duo' });
        await waitForPromises();

        expect(findOffCapabilities().at(0).text()).toBe(
          'SAST false positive detection Off for Root group. Turn it on in GitLab Duo settings',
        );
        expect(findOffCapabilities().at(0).findComponent(GlLink).exists()).toBe(false);
        expect(wrapper.findAllByTestId('duo-settings-link')).toHaveLength(1);
        expect(wrapper.findByTestId('duo-settings-link').text()).toBe('View GitLab Duo settings');
        expect(wrapper.findByTestId('duo-settings-link').attributes('href')).toBe(
          '/groups/root/-/settings/gitlab_duo',
        );
        expect(findOffCard().text()).not.toContain('Waiting on the Owner');
      });
    });

    describe('for a user who cannot change GitLab Duo settings', () => {
      it('shows the Owner it waits on', async () => {
        createComponent({ statuses });
        await waitForPromises();

        expect(findOffCapabilities().at(0).text()).toContain('Waiting on the Owner of Root group');
        expect(wrapper.findByTestId('duo-settings-link').exists()).toBe(false);
      });
    });
  });

  describe('when capabilities in the preset are not applicable or have no status', () => {
    beforeEach(async () => {
      createComponent({
        statuses: { SBOM_INGESTED: 'NOT_APPLICABLE' },
      });
      await waitForPromises();
    });

    it('shows NOT_APPLICABLE as ready', () => {
      expect(findCount(findReadyCard())).toBe('1 capability');
      expect(findTitles(findReadyCapabilities())).toEqual(['Dependency scanning auto-remediation']);
    });

    it('hides the one with no status', () => {
      expect(wrapper.text()).not.toContain('Secret detection false positive detection');
    });
  });

  it('shows an error for a failed load', async () => {
    createComponent({ handler: jest.fn().mockRejectedValue(new Error('error')) });
    await waitForPromises();

    expect(findAlert().props('variant')).toBe('danger');
    expect(findAlert().text()).toBe('Could not check which capabilities can run. Try again later.');
  });

  describe('when a capability in the preset has an unavailable flow', () => {
    beforeEach(async () => {
      createComponent({
        statuses: {
          SAST_FALSE_POSITIVE: 'FLOW_UNAVAILABLE',
          SBOM_INGESTED: 'FLOW_NOT_ENABLED',
          SECRET_DETECTION_FALSE_POSITIVE: 'AVAILABLE',
        },
      });
      await waitForPromises();
    });

    it("hides it from the Won't run yet card", () => {
      expect(findTitles(findOffCapabilities())).toEqual(['Dependency scanning auto-remediation']);
    });

    it('hides it from the Ready card', () => {
      expect(findTitles(findReadyCapabilities())).toEqual([
        'Secret detection false positive detection',
      ]);
    });
  });

  describe('group Owners footer link', () => {
    const statuses = { SAST_FALSE_POSITIVE: 'FLOW_NOT_ENABLED' };
    const groupOwnersPath = '/groups/root/-/group_members?access_level=50';
    const findGroupOwnersLink = () => wrapper.findByTestId('group-owners-link');

    it('links to the group Owners', async () => {
      createComponent({ statuses, groupOwnersPath });
      await waitForPromises();

      expect(findOffCard().text()).toContain('Ask a group Owner to turn them on.');
      expect(findGroupOwnersLink().text()).toBe('group Owner');
      expect(findGroupOwnersLink().attributes('href')).toBe(groupOwnersPath);
      expect(wrapper.findByTestId('duo-settings-link').exists()).toBe(false);
    });

    it('hides it beside the GitLab Duo settings link', async () => {
      createComponent({
        statuses,
        groupOwnersPath,
        duoSettingsPath: '/groups/root/-/settings/gitlab_duo',
      });
      await waitForPromises();

      expect(wrapper.findByTestId('duo-settings-link').exists()).toBe(true);
      expect(findGroupOwnersLink().exists()).toBe(false);
    });

    it('hides it without a group Owners path', async () => {
      createComponent({ statuses });
      await waitForPromises();

      expect(findGroupOwnersLink().exists()).toBe(false);
    });
  });

  it('handles a failed load by reporting it', async () => {
    const error = new Error('GraphQL error');
    jest.spyOn(Sentry, 'captureException');
    createComponent({ handler: jest.fn().mockRejectedValue(error) });
    await waitForPromises();

    expect(Sentry.captureException).toHaveBeenCalledWith(error);
  });
});
