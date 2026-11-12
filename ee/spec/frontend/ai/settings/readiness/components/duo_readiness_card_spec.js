import Vue from 'vue';
import VueApollo from 'vue-apollo';
import { GlProgressBar } from '@gitlab/ui';
import { mountExtended } from 'helpers/vue_test_utils_helper';
import createMockApollo from 'helpers/mock_apollo_helper';
import waitForPromises from 'helpers/wait_for_promises';
import DuoReadinessCard from '~/ai/settings/readiness/components/duo_readiness_card.vue';
import DuoReadinessRow from '~/ai/settings/readiness/components/duo_readiness_row.vue';
import DuoReadinessAgentConfigRow from 'ee/ai/settings/readiness/components/duo_readiness_agent_config_row.vue';
import DuoReadinessInheritedList from 'ee/ai/settings/readiness/components/duo_readiness_inherited_list.vue';
import runnerAvailableQuery from 'ee/ai/settings/readiness/graphql/queries/duo_workflow_runner_available.query.graphql';
import duoMcpServerNamesQuery from 'ee/ai/settings/readiness/graphql/queries/duo_mcp_server_names.query.graphql';

Vue.use(VueApollo);

describe('DuoReadinessCard', () => {
  let wrapper;

  const runnerResponse = (available) => ({
    data: {
      project: {
        id: 'gid://gitlab/Project/1',
        duoWorkflowRunnerAvailable: available,
        duoWorkflowUsableRunnerType: available ? 'instance_type' : null,
      },
    },
  });

  const createComponent = ({ runnerAvailable = true, ...props } = {}) => {
    wrapper = mountExtended(DuoReadinessCard, {
      apolloProvider: createMockApollo([
        [runnerAvailableQuery, jest.fn().mockResolvedValue(runnerResponse(runnerAvailable))],
        [
          duoMcpServerNamesQuery,
          jest.fn().mockResolvedValue({
            data: { project: { id: 'gid://gitlab/Project/1', duoMcpServerNames: [] } },
          }),
        ],
      ]),
      propsData: {
        duoEnabledSetting: {
          label: 'GitLab Duo',
          helpText: 'Use AI-native features in this project.',
          helpPath: '/help/user/gitlab_duo/_index',
        },
        duoReadiness: {
          platformEnabled: true,
          runnersPath: '/g/p/-/settings/ci_cd',
          agentConfigPresent: true,
        },
        projectFullPath: 'g/p',
        duoEnabled: true,
        duoRemoteFlowsAvailability: true,
        ...props,
      },
    });
  };

  const findCount = () => wrapper.findByTestId('readiness-progress-count');
  const findStateLine = () => wrapper.findByTestId('readiness-state-line');
  const findProgressBar = () => wrapper.findComponent(GlProgressBar);

  describe('progress header', () => {
    it('counts the runner only once its check resolves', async () => {
      createComponent();

      expect(findCount().text()).toBe('1 step left');

      await waitForPromises();

      expect(findCount().text()).toBe('All steps complete');
      expect(findProgressBar().props()).toMatchObject({
        value: 4,
        max: 4,
        variant: 'success',
        ariaLabel: 'Agent setup progress: 4 of 4 steps complete',
      });
    });

    describe('when every required step is done', () => {
      beforeEach(async () => {
        createComponent();
        await waitForPromises();
      });

      it('reads ready', () => {
        expect(findStateLine().text()).toBe('Ready. Flows can run in this project.');
      });
    });

    describe('when the Agent Platform is off above the project', () => {
      beforeEach(async () => {
        createComponent({
          duoReadiness: { platformEnabled: false, runnersPath: '/g/p/-/settings/ci_cd' },
        });
        await waitForPromises();
      });

      it('reads blocked', () => {
        expect(findStateLine().text()).toBe(
          'Blocked: the Agent Platform is off, so nothing below can be set up yet.',
        );
      });
    });

    describe('when GitLab Duo is off', () => {
      beforeEach(async () => {
        createComponent({ duoEnabled: false });
        await waitForPromises();
      });

      it('reads not set up', () => {
        expect(findStateLine().text()).toBe('Not set up yet. To get started, turn on GitLab Duo.');
      });

      it('counts two steps left', () => {
        expect(findCount().text()).toBe('2 steps left');
        expect(findProgressBar().props('ariaLabel')).toBe(
          'Agent setup progress: 2 of 4 steps complete',
        );
      });
    });

    describe('when flow execution is off', () => {
      beforeEach(async () => {
        createComponent({ duoRemoteFlowsAvailability: false });
        await waitForPromises();
      });

      it('names the working features', () => {
        expect(findStateLine().text()).toBe(
          'Chat and Code Suggestions work today. 1 more step to set up flows.',
        );
      });
    });

    describe('when only the runner is missing', () => {
      beforeEach(async () => {
        createComponent({ runnerAvailable: false });
        await waitForPromises();
      });

      it('reads steps remaining', () => {
        expect(findCount().text()).toBe('1 step left');
        expect(findStateLine().text()).toBe('1 step left to set up flows.');
      });
    });

    it('caps the total at the four counted rows', async () => {
      createComponent({ duoFoundationalFlowsAvailability: true });
      await waitForPromises();

      expect(findCount().text()).toBe('All steps complete');
    });

    it('does not count the agent configuration file', async () => {
      createComponent({
        duoReadiness: {
          platformEnabled: true,
          runnersPath: '/g/p/-/settings/ci_cd',
          agentConfigPresent: false,
        },
      });
      await waitForPromises();

      expect(findCount().text()).toBe('All steps complete');
      expect(findStateLine().text()).toBe('Ready. Flows can run in this project.');
    });
  });

  describe('recommended group', () => {
    const findGroup = () => wrapper.findByTestId('duo-recommended-group');

    it('renders the agent configuration file as its first row', async () => {
      createComponent();
      await waitForPromises();

      expect(findGroup().text()).toContain('Recommended');
      expect(findGroup().text()).toContain(
        'Flows run without these. Set them up for the best results.',
      );
      expect(findGroup().findComponent(DuoReadinessAgentConfigRow).exists()).toBe(true);
      expect(findGroup().findAllByTestId('readiness-row').at(0).text()).toContain(
        'Agent configuration file',
      );
    });

    it('is hidden when the Agent Platform is off above the project', async () => {
      createComponent({
        duoReadiness: { platformEnabled: false, runnersPath: '/g/p/-/settings/ci_cd' },
      });
      await waitForPromises();

      expect(findGroup().exists()).toBe(false);
    });
  });

  describe('scheduled automations row', () => {
    const LOCKED_BY_ANCESTOR = {
      lockedByAncestor: true,
      lockedByApplicationSetting: false,
      ancestorNamespace: { fullName: 'parent-group', path: '/parent-group' },
    };
    const LOCKED_BY_APPLICATION_SETTING = {
      lockedByAncestor: false,
      lockedByApplicationSetting: true,
    };
    const PLATFORM_OFF = { platformEnabled: false, runnersPath: '/g/p/-/settings/ci_cd' };

    const findScheduledTriggersRow = () => wrapper.findComponentByTestId('scheduled-triggers-row');
    const findScheduledTriggersToggle = () =>
      wrapper.findComponentByTestId('duo-scheduled-triggers-enabled');
    const findScheduledTriggersLockIcon = () =>
      wrapper.findComponentByTestId('duo-scheduled-triggers-cascading-lock-icon');

    it('posts under the project_setting_attributes name the form submits', async () => {
      createComponent();
      await waitForPromises();

      expect(findScheduledTriggersToggle().props('name')).toBe(
        'project[project_setting_attributes][duo_scheduled_triggers_enabled]',
      );
      expect(
        wrapper
          .find('input[name="project[project_setting_attributes][duo_scheduled_triggers_enabled]"]')
          .exists(),
      ).toBe(true);
    });

    it.each([true, false])('shows the toggle at the availability given (%s)', async (value) => {
      createComponent({ duoScheduledTriggersAvailability: value });
      await waitForPromises();

      expect(findScheduledTriggersToggle().props('value')).toBe(value);
    });

    it('emits the change back to the parent form', async () => {
      createComponent();
      await waitForPromises();

      findScheduledTriggersToggle().vm.$emit('change', false);

      expect(wrapper.emitted('update:duo-scheduled-triggers-availability')).toEqual([[false]]);
    });

    it.each`
      status       | scenario                           | props
      ${'done'}    | ${'scheduled automations are on'}  | ${{}}
      ${'todo'}    | ${'scheduled automations are off'} | ${{ duoScheduledTriggersAvailability: false }}
      ${'blocked'} | ${'flow execution is off'}         | ${{ duoRemoteFlowsAvailability: false }}
      ${'blocked'} | ${'GitLab Duo is off'}             | ${{ duoEnabled: false }}
      ${'blocked'} | ${'the Agent Platform is off'}     | ${{ duoReadiness: PLATFORM_OFF }}
    `('reads $status when $scenario', async ({ status, props }) => {
      createComponent(props);
      await waitForPromises();

      expect(findScheduledTriggersRow().props('status')).toBe(status);
    });

    it.each`
      scenario                       | props
      ${'flow execution is off'}     | ${{ duoRemoteFlowsAvailability: false }}
      ${'GitLab Duo is off'}         | ${{ duoEnabled: false }}
      ${'the Agent Platform is off'} | ${{ duoReadiness: PLATFORM_OFF }}
    `('is disabled when $scenario', async ({ props }) => {
      createComponent(props);
      await waitForPromises();

      expect(findScheduledTriggersToggle().props('disabled')).toBe(true);
    });

    it.each`
      scenario                    | props
      ${'an ancestor locked it'}  | ${{ duoScheduledTriggersCascadingSettings: LOCKED_BY_ANCESTOR }}
      ${'the instance locked it'} | ${{ duoScheduledTriggersCascadingSettings: LOCKED_BY_APPLICATION_SETTING }}
    `('is disabled when $scenario', async ({ props }) => {
      createComponent(props);
      await waitForPromises();

      expect(findScheduledTriggersToggle().props('disabled')).toBe(true);
    });

    it('is enabled by default', async () => {
      createComponent();
      await waitForPromises();

      expect(findScheduledTriggersToggle().props('disabled')).toBe(false);
    });

    it('names the locking ancestor on the lock icon', async () => {
      createComponent({ duoScheduledTriggersCascadingSettings: LOCKED_BY_ANCESTOR });
      await waitForPromises();

      expect(findScheduledTriggersLockIcon().props()).toMatchObject({
        isLockedByGroupAncestor: true,
        isLockedByApplicationSettings: false,
        ancestorNamespace: LOCKED_BY_ANCESTOR.ancestorNamespace,
      });
    });

    it('marks the lock icon as an instance lock', async () => {
      createComponent({ duoScheduledTriggersCascadingSettings: LOCKED_BY_APPLICATION_SETTING });
      await waitForPromises();

      expect(findScheduledTriggersLockIcon().props()).toMatchObject({
        isLockedByGroupAncestor: false,
        isLockedByApplicationSettings: true,
      });
    });

    it('shows no lock icon by default', async () => {
      createComponent();
      await waitForPromises();

      expect(findScheduledTriggersLockIcon().exists()).toBe(false);
    });
  });

  describe('settings state contract', () => {
    it('emits toggle changes back to the parent form', async () => {
      createComponent();
      await waitForPromises();

      wrapper.findComponentByTestId('duo_features_enabled_toggle').vm.$emit('change', false);
      wrapper.findComponentByTestId('duo-remote-flows-enabled').vm.$emit('change', false);

      expect(wrapper.emitted('update:duo-enabled')).toEqual([[false]]);
      expect(wrapper.emitted('update:duo-remote-flows-availability')).toEqual([[false]]);
    });

    it('links Learn more on the GitLab Duo row', async () => {
      createComponent();
      await waitForPromises();

      const link = wrapper.findByTestId('duo-row-help-link');

      expect(link.text()).toBe('Learn more');
      expect(link.attributes('href')).toBe('/help/user/gitlab_duo/_index');
      expect(link.attributes('target')).toBe('_blank');
    });

    it('keeps the toggle form fields, so the settings form still submits them', async () => {
      createComponent();
      await waitForPromises();

      expect(
        wrapper
          .find('input[name="project[project_setting_attributes][duo_features_enabled]"]')
          .exists(),
      ).toBe(true);
      expect(
        wrapper
          .find('input[name="project[project_setting_attributes][duo_remote_flows_enabled]"]')
          .exists(),
      ).toBe(true);
    });
  });

  describe('foundational flows the top-level group picked', () => {
    const foundationalFlows = [
      { reference: 'code_review/v1', name: 'Code Review' },
      { reference: 'developer/v1', name: 'Developer' },
    ];
    const duoReadiness = {
      platformEnabled: true,
      runnersPath: '/g/p/-/settings/ci_cd',
      rootGroupName: 'my-group',
      groupSettingsPath: '/groups/my-group/-/settings/gitlab_duo',
      foundationalFlows,
    };

    const findFoundationalFlowsRow = () =>
      wrapper
        .findAllComponents(DuoReadinessRow)
        .wrappers.find((row) => row.attributes('data-testid') === 'foundational-flows-row');
    const findDescription = () =>
      findFoundationalFlowsRow().find('[data-testid="readiness-row-description"]');
    const findGroupLink = () => wrapper.findByTestId('foundational-flows-group-link');
    const findList = () =>
      findFoundationalFlowsRow().find('[data-testid="foundational-flow-list"]');

    it('lists them inside the foundational flows row and names the group that picked them', async () => {
      createComponent({ duoReadiness });
      await waitForPromises();

      expect(findDescription().text()).toBe(
        'Production-ready flows built and maintained by GitLab. Set by my-group.',
      );
      expect(findGroupLink().attributes('href')).toBe('/groups/my-group/-/settings/gitlab_duo');
      expect(
        findList()
          .findAll('li')
          .wrappers.map((item) => item.text()),
      ).toEqual(['Code Review', 'Developer']);
      expect(findList().classes()).not.toContain('gl-text-disabled');
    });

    describe('when the group settings are not reachable', () => {
      beforeEach(async () => {
        createComponent({ duoReadiness: { ...duoReadiness, groupSettingsPath: null } });
        await waitForPromises();
      });

      it('names the group without a link', () => {
        expect(findGroupLink().exists()).toBe(false);
        expect(findDescription().text()).toBe(
          'Production-ready flows built and maintained by GitLab. Set by my-group.',
        );
      });
    });

    describe('while flow execution is off', () => {
      beforeEach(async () => {
        createComponent({ duoReadiness, duoRemoteFlowsAvailability: false });
        await waitForPromises();
      });

      it('mutes the list', () => {
        expect(findList().classes()).toContain('gl-text-disabled');
      });
    });

    describe('when the group picked nothing', () => {
      beforeEach(async () => {
        createComponent();
        await waitForPromises();
      });

      it('keeps the plain description and shows no list', () => {
        expect(findDescription().text()).toBe(
          'Production-ready flows built and maintained by GitLab.',
        );
        expect(findList().exists()).toBe(false);
      });
    });
  });

  describe('foundational agents the top-level group turned on', () => {
    const foundationalAgents = [
      { reference: 'planner_agent', name: 'Planner' },
      { reference: 'security_analyst_agent', name: 'Security Analyst' },
    ];
    const duoReadiness = {
      platformEnabled: true,
      runnersPath: '/g/p/-/settings/ci_cd',
      rootGroupName: 'my-group',
      groupSettingsPath: '/groups/my-group/-/settings/gitlab_duo',
      foundationalAgents,
    };

    const rowTestIds = () =>
      wrapper
        .findAllComponents(DuoReadinessRow)
        .wrappers.map((row) => row.attributes('data-testid'));
    const findAgentsRow = () =>
      wrapper
        .findAllComponents(DuoReadinessRow)
        .wrappers.find((row) => row.attributes('data-testid') === 'foundational-agents-row');
    const findList = () =>
      wrapper
        .findAllComponents(DuoReadinessInheritedList)
        .wrappers.find((list) => list.attributes('data-testid') === 'foundational-agent-list-row');

    it('reports them under the GitLab Duo row, without a status, and names the group', async () => {
      createComponent({ duoReadiness });
      await waitForPromises();

      expect(rowTestIds().indexOf('foundational-agents-row')).toBe(
        rowTestIds().indexOf('duo-row') + 1,
      );
      expect(findAgentsRow().props('status')).toBeNull();
      expect(findAgentsRow().find('[data-testid="readiness-row-description"]').text()).toBe(
        'This project can use these agents built and maintained by GitLab. Set by my-group.',
      );
      expect(wrapper.findByTestId('foundational-agents-group-link').attributes('href')).toBe(
        '/groups/my-group/-/settings/gitlab_duo',
      );
      expect(findList().props('items')).toEqual(foundationalAgents);
      expect(
        findList()
          .findAll('li')
          .wrappers.map((item) => item.text()),
      ).toEqual(['Planner', 'Security Analyst']);
    });

    it('does not count towards the required steps', async () => {
      createComponent({ duoReadiness, duoEnabled: false });
      await waitForPromises();

      expect(findCount().text()).toBe('2 steps left');
    });

    it('keeps the row and the list live while both gates are on', async () => {
      createComponent({ duoReadiness });
      await waitForPromises();

      expect(findAgentsRow().props('disabled')).toBe(false);
      expect(findList().props('disabled')).toBe(false);
    });

    it.each`
      gate                    | props
      ${'the Agent Platform'} | ${{ duoReadiness: { ...duoReadiness, platformEnabled: false } }}
      ${'GitLab Duo'}         | ${{ duoReadiness, duoEnabled: false }}
    `('mutes the row and the list while $gate is off for the project', async ({ props }) => {
      createComponent(props);
      await waitForPromises();

      expect(findAgentsRow().props('disabled')).toBe(true);
      expect(findList().props('disabled')).toBe(true);
    });

    describe('when the group settings are not reachable', () => {
      beforeEach(async () => {
        createComponent({ duoReadiness: { ...duoReadiness, groupSettingsPath: null } });
        await waitForPromises();
      });

      it('names the group without a link', () => {
        expect(wrapper.findByTestId('foundational-agents-group-link').exists()).toBe(false);
        expect(findAgentsRow().find('[data-testid="readiness-row-description"]').text()).toBe(
          'This project can use these agents built and maintained by GitLab. Set by my-group.',
        );
      });
    });

    describe('when the group turned nothing on', () => {
      beforeEach(async () => {
        createComponent({ duoReadiness: { ...duoReadiness, foundationalAgents: [] } });
        await waitForPromises();
      });

      it('says so in the row and shows no list', () => {
        expect(findAgentsRow().find('[data-testid="readiness-row-description"]').text()).toBe(
          'No foundational agents are turned on by my-group.',
        );
        expect(findList()).toBeUndefined();
      });
    });

    describe('when no top-level group reports agents to the project', () => {
      beforeEach(async () => {
        createComponent({ duoReadiness: { ...duoReadiness, foundationalAgents: null } });
        await waitForPromises();
      });

      it('shows neither the row nor the list', () => {
        expect(findAgentsRow()).toBeUndefined();
        expect(findList()).toBeUndefined();
      });
    });
  });
});
