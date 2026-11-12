import Vue from 'vue';
import VueApollo from 'vue-apollo';
import { GlAlert, GlIcon, GlLink } from '@gitlab/ui';
import { mountExtended } from 'helpers/vue_test_utils_helper';
import createMockApollo from 'helpers/mock_apollo_helper';
import waitForPromises from 'helpers/wait_for_promises';
import { useFakeDate } from 'helpers/fake_date';
import { useMockInternalEventsTracking } from 'helpers/tracking_internal_events_helper';
import AgentInventoryCard from 'ee/ai/governance/components/dashboard/cards/agent_inventory_card.vue';
import getDashboardConfiguredAgentsQuery from 'ee/ai/governance/graphql/queries/get_dashboard_configured_agents.query.graphql';
import getConnectedAgentsQuery from 'ee/ai/governance/graphql/queries/get_connected_agents.query.graphql';

Vue.use(VueApollo);

const consumerNode = (id, name, { project = null } = {}) => ({
  __typename: 'AiCatalogItemConsumer',
  id: `gid://gitlab/Ai::Catalog::ItemConsumer/${id}`,
  item: {
    __typename: 'AiCatalogAgent',
    id: `gid://gitlab/Ai::Catalog::Item/${id}`,
    name,
    itemType: 'agent',
    description: `${name} description`,
    project: project
      ? { __typename: 'Project', id: `gid://gitlab/Project/${id}`, nameWithNamespace: project }
      : null,
  },
});

const configuredItemsResponse = (nodes) => ({
  data: {
    aiCatalogConfiguredItems: {
      __typename: 'AiCatalogItemConsumerConnection',
      nodes,
    },
  },
});

const connectedAgentNode = (agentType, { activeCount = 3, userCount = 2 } = {}) => ({
  __typename: 'AiGovernanceConnectedAgent',
  agentType,
  activeCount,
  userCount,
});

const connectedAgentsResponse = (nodes) => ({
  data: {
    group: {
      __typename: 'Group',
      id: 'gid://gitlab/Group/1',
      aiGovernanceMetrics: {
        __typename: 'AiGovernanceMetrics',
        connectedAgents: nodes,
      },
    },
  },
});

const projectConnectedAgentsResponse = (nodes) => ({
  data: {
    project: {
      __typename: 'Project',
      id: 'gid://gitlab/Project/2',
      aiGovernanceMetrics: {
        __typename: 'AiGovernanceMetrics',
        connectedAgents: nodes,
      },
    },
  },
});

describe('AgentInventoryCard', () => {
  let wrapper;

  const createComponent = ({ provide = {}, props = {}, handler, connectedHandler } = {}) => {
    const apolloProvider = createMockApollo([
      [
        getDashboardConfiguredAgentsQuery,
        handler ?? jest.fn().mockResolvedValue(configuredItemsResponse([])),
      ],
      [
        getConnectedAgentsQuery,
        connectedHandler ?? jest.fn().mockResolvedValue(connectedAgentsResponse([])),
      ],
    ]);

    wrapper = mountExtended(AgentInventoryCard, {
      apolloProvider,
      propsData: props,
      provide: {
        groupId: '1',
        projectId: null,
        groupFullPath: 'gitlab-duo',
        projectFullPath: null,
        glFeatures: { aiGovernanceSessionsApi: true, aiGovernanceAuditEventsFilters: true },
        ...provide,
      },
    });
  };

  const findRows = () => wrapper.findAllByTestId('agent-inventory-row');
  const findEmptyState = () => wrapper.findByTestId('empty-state');
  const findAlert = () => wrapper.findComponent(GlAlert);
  const findViewAllLink = () => wrapper.findByTestId('view-all-link');

  it('renders a row per configured agent', async () => {
    createComponent({
      handler: jest
        .fn()
        .mockResolvedValue(configuredItemsResponse([consumerNode(1, 'Release agent')])),
    });
    await waitForPromises();

    expect(findRows()).toHaveLength(1);
    expect(findRows().at(0).text()).toContain('Release agent');
    expect(findRows().at(0).text()).toContain('Release agent description');
  });

  it('renders agents in the order returned by the backend', async () => {
    createComponent({
      handler: jest
        .fn()
        .mockResolvedValue(
          configuredItemsResponse([
            consumerNode(1, 'Popular agent'),
            consumerNode(2, 'Middling agent'),
            consumerNode(3, 'Idle agent'),
          ]),
        ),
    });
    await waitForPromises();

    const names = findRows().wrappers.map((row) => row.find('[data-testid="agent-name"]').text());
    expect(names).toEqual(['Popular agent', 'Middling agent', 'Idle agent']);
  });

  it('requests the top agents sorted by usage, scoped to the group', async () => {
    const handler = jest.fn().mockResolvedValue(configuredItemsResponse([]));
    createComponent({ handler });
    await waitForPromises();

    expect(handler).toHaveBeenCalledWith(
      expect.objectContaining({
        groupId: 'gid://gitlab/Group/1',
        itemTypes: ['AGENT'],
        first: 5,
        sort: 'USAGE_COUNT_DESC',
        includeFoundationalConsumers: true,
      }),
    );
  });

  it('uses the project as the subtitle to disambiguate same-named agents', async () => {
    createComponent({
      handler: jest
        .fn()
        .mockResolvedValue(
          configuredItemsResponse([
            consumerNode(1, 'ACME-Security-Analyst', { project: 'Group / acme-corp-1' }),
            consumerNode(2, 'ACME-Security-Analyst', { project: 'Group / acme-corp-2' }),
          ]),
        ),
    });
    await waitForPromises();

    expect(findRows()).toHaveLength(2);
    expect(findRows().at(0).text()).toContain('Group / acme-corp-1');
    expect(findRows().at(1).text()).toContain('Group / acme-corp-2');
  });

  it('requests the top agents sorted by usage, scoped to the project in project mode', async () => {
    const handler = jest.fn().mockResolvedValue(configuredItemsResponse([]));
    createComponent({ provide: { projectId: '2', projectFullPath: 'gitlab-duo/test' }, handler });
    await waitForPromises();

    expect(handler).toHaveBeenCalledWith(
      expect.objectContaining({
        projectId: 'gid://gitlab/Project/2',
        itemTypes: ['AGENT'],
        first: 5,
        sort: 'USAGE_COUNT_DESC',
      }),
    );
  });

  it('builds the "View all agents" link to the group agents page', async () => {
    createComponent();
    await waitForPromises();

    expect(findViewAllLink().attributes('href')).toBe('/groups/gitlab-duo/-/automate/agents');
  });

  it('shows the empty state when no agents are configured', async () => {
    createComponent();
    await waitForPromises();

    expect(findRows()).toHaveLength(0);
    expect(findEmptyState().exists()).toBe(true);
  });

  it('shows an error alert when the query fails', async () => {
    createComponent({ handler: jest.fn().mockRejectedValue(new Error('failed')) });
    await waitForPromises();

    expect(findAlert().exists()).toBe(true);
  });

  it('clears the error once a refetch succeeds', async () => {
    const connectedHandler = jest
      .fn()
      .mockRejectedValueOnce(new Error('failed'))
      .mockResolvedValue(connectedAgentsResponse([connectedAgentNode('claude-code')]));
    createComponent({ connectedHandler });
    await waitForPromises();

    expect(findAlert().exists()).toBe(true);

    wrapper.setProps({ agentClass: 'EXTERNAL' });
    await waitForPromises();

    expect(findAlert().exists()).toBe(false);
  });
  describe('agent class', () => {
    const names = () =>
      findRows().wrappers.map((row) => row.find('[data-testid="agent-name"]').text());

    it('lists connected agents alongside catalog agents by default', async () => {
      createComponent({
        handler: jest
          .fn()
          .mockResolvedValue(configuredItemsResponse([consumerNode(1, 'Release agent')])),
        connectedHandler: jest
          .fn()
          .mockResolvedValue(connectedAgentsResponse([connectedAgentNode('claude-code')])),
      });
      await waitForPromises();

      expect(names()).toEqual(['Claude Code', 'Release agent']);
    });

    it('requests connected agents for the ALL class by default', async () => {
      const connectedHandler = jest.fn().mockResolvedValue(connectedAgentsResponse([]));
      createComponent({ connectedHandler });
      await waitForPromises();

      expect(connectedHandler).toHaveBeenCalledWith(
        expect.objectContaining({ agentClass: 'ALL', limit: 5 }),
      );
    });

    it('describes a connected agent by its registered machines and users', async () => {
      createComponent({
        props: { agentClass: 'EXTERNAL' },
        connectedHandler: jest
          .fn()
          .mockResolvedValue(
            connectedAgentsResponse([
              connectedAgentNode('claude-code', { activeCount: 4, userCount: 1 }),
            ]),
          ),
      });
      await waitForPromises();

      expect(findRows().at(0).text()).toContain('4 machines');
      expect(findRows().at(0).text()).toContain('1 user');
    });

    it.each([
      ['cursor', 'file-mock-cursor.svg'],
      ['codex', 'file-mock-codex.svg'],
    ])('shows the %s logo on a connected agent', async (agentType, logo) => {
      createComponent({
        props: { agentClass: 'EXTERNAL' },
        connectedHandler: jest
          .fn()
          .mockResolvedValue(connectedAgentsResponse([connectedAgentNode(agentType)])),
      });
      await waitForPromises();

      const img = findRows().at(0).find('[data-testid="agent-logo"]');
      expect(img.element.src).toBe(logo);
      expect(img.classes('gl-scale-150')).toBe(agentType === 'codex');
      // The logo replaces the connected icon; a linked row still ends in a chevron.
      expect(
        findRows()
          .at(0)
          .findAllComponents(GlIcon)
          .wrappers.map((icon) => icon.props('name')),
      ).not.toContain('connected');
    });

    it('keeps the connected icon for an agent type with no logo', async () => {
      createComponent({
        props: { agentClass: 'EXTERNAL' },
        connectedHandler: jest
          .fn()
          .mockResolvedValue(connectedAgentsResponse([connectedAgentNode('claude-code')])),
      });
      await waitForPromises();

      expect(findRows().at(0).find('[data-testid="agent-logo"]').exists()).toBe(false);
      expect(findRows().at(0).findComponent(GlIcon).props('name')).toBe('connected');
    });

    it('shows only catalog agents for INTERNAL_DAP', async () => {
      const connectedHandler = jest.fn().mockResolvedValue(connectedAgentsResponse([]));
      createComponent({
        props: { agentClass: 'INTERNAL_DAP' },
        handler: jest
          .fn()
          .mockResolvedValue(configuredItemsResponse([consumerNode(1, 'Release agent')])),
        connectedHandler,
      });
      await waitForPromises();

      expect(names()).toEqual(['Release agent']);
      expect(connectedHandler).not.toHaveBeenCalled();
    });

    it.each([
      ['claude-code', 'Claude Code'],
      ['cursor', 'Cursor'],
      ['codex', 'Codex'],
    ])('names the %s connected agent by its product name', async (agentType, name) => {
      createComponent({
        props: { agentClass: 'EXTERNAL' },
        connectedHandler: jest
          .fn()
          .mockResolvedValue(connectedAgentsResponse([connectedAgentNode(agentType)])),
      });
      await waitForPromises();

      expect(names()).toEqual([name]);
    });

    it('shows only connected agents for EXTERNAL', async () => {
      const handler = jest.fn().mockResolvedValue(configuredItemsResponse([]));
      createComponent({
        props: { agentClass: 'EXTERNAL' },
        handler,
        connectedHandler: jest
          .fn()
          .mockResolvedValue(connectedAgentsResponse([connectedAgentNode('claude-code')])),
      });
      await waitForPromises();

      expect(names()).toEqual(['Claude Code']);
      expect(handler).not.toHaveBeenCalled();
    });

    it('drops the catalog agents once the class changes to EXTERNAL', async () => {
      createComponent({
        handler: jest
          .fn()
          .mockResolvedValue(configuredItemsResponse([consumerNode(1, 'Release agent')])),
        connectedHandler: jest
          .fn()
          .mockResolvedValue(connectedAgentsResponse([connectedAgentNode('claude-code')])),
      });
      await waitForPromises();

      await wrapper.setProps({ agentClass: 'EXTERNAL' });
      await waitForPromises();

      expect(names()).toEqual(['Claude Code']);
    });

    it('re-runs the connected agents query when the class changes', async () => {
      const connectedHandler = jest.fn().mockResolvedValue(connectedAgentsResponse([]));
      createComponent({ connectedHandler });
      await waitForPromises();

      await wrapper.setProps({ agentClass: 'EXTERNAL' });
      await waitForPromises();

      expect(connectedHandler).toHaveBeenLastCalledWith(
        expect.objectContaining({ agentClass: 'EXTERNAL' }),
      );
    });

    it('queries connected agents on the project in project mode', async () => {
      const connectedHandler = jest
        .fn()
        .mockResolvedValue(projectConnectedAgentsResponse([connectedAgentNode('claude-code')]));
      createComponent({
        props: { agentClass: 'EXTERNAL' },
        provide: { projectId: '2', projectFullPath: 'gitlab-duo/test' },
        connectedHandler,
      });
      await waitForPromises();

      expect(connectedHandler).toHaveBeenCalledWith(
        expect.objectContaining({ projectFullPath: 'gitlab-duo/test', isProject: true }),
      );
      expect(names()).toEqual(['Claude Code']);
    });
  });

  describe('agent links', () => {
    useFakeDate(2026, 9, 19, 10);

    const findRowLink = () => findRows().at(0).findComponent(GlLink);
    const findIconNames = (element) =>
      element.findAllComponents(GlIcon).wrappers.map((icon) => icon.props('name'));

    it('links the whole row of a catalog agent to its page under the group', async () => {
      createComponent({
        handler: jest
          .fn()
          .mockResolvedValue(configuredItemsResponse([consumerNode(7, 'Release agent')])),
      });
      await waitForPromises();

      expect(findRowLink().attributes('href')).toBe('/groups/gitlab-duo/-/automate/agents/7');
      expect(findRowLink().find('[data-testid="agent-name"]').text()).toBe('Release agent');
      expect(findIconNames(findRowLink())).toEqual(['tanuki-ai', 'chevron-right']);
    });

    it('links a catalog agent to its page under the project in project mode', async () => {
      createComponent({
        provide: { projectId: '2', projectFullPath: 'gitlab-duo/test' },
        handler: jest
          .fn()
          .mockResolvedValue(configuredItemsResponse([consumerNode(7, 'Release agent')])),
        connectedHandler: jest.fn().mockResolvedValue(projectConnectedAgentsResponse([])),
      });
      await waitForPromises();

      expect(findRowLink().attributes('href')).toBe('/gitlab-duo/test/-/automate/agents/7');
    });

    it('links a connected agent to its connected sessions of the last 30 days', async () => {
      createComponent({
        props: { agentClass: 'EXTERNAL' },
        connectedHandler: jest
          .fn()
          .mockResolvedValue(connectedAgentsResponse([connectedAgentNode('claude-code')])),
      });
      await waitForPromises();

      expect(findRowLink().attributes('href')).toBe(
        '?tab=agent-artifacts&agentType=claude-code&agentClass=EXTERNAL&startTimeAfter=2026-09-19',
      );
      expect(findIconNames(findRows().at(0))).toEqual(['connected', 'chevron-right']);
    });

    it.each`
      description                  | glFeatures
      ${'the sessions API is off'} | ${{ aiGovernanceSessionsApi: false, aiGovernanceAuditEventsFilters: true }}
      ${'the filters flag is off'} | ${{ aiGovernanceSessionsApi: true, aiGovernanceAuditEventsFilters: false }}
    `('leaves a connected agent as plain text when $description', async ({ glFeatures }) => {
      createComponent({
        props: { agentClass: 'EXTERNAL' },
        provide: { glFeatures },
        connectedHandler: jest
          .fn()
          .mockResolvedValue(connectedAgentsResponse([connectedAgentNode('claude-code')])),
      });
      await waitForPromises();

      expect(findRowLink().exists()).toBe(false);
      expect(findRows().at(0).find('[data-testid="agent-name"]').text()).toBe('Claude Code');
      expect(findIconNames(findRows().at(0))).toEqual(['connected']);
      expect(findRows().at(0).find('[data-event-tracking]').exists()).toBe(false);
    });
  });

  describe('in the side panel', () => {
    useFakeDate(2026, 9, 19, 10);

    let openGovernancePanel;

    // Returns whether the card took over the click, and stops jsdom from navigating.
    const clickRow = (init = {}) => {
      let preventedByCard;
      const stopNavigation = (event) => {
        preventedByCard = event.defaultPrevented;
        event.preventDefault();
      };

      wrapper.element.addEventListener('click', stopNavigation);
      findRows()
        .at(0)
        .findComponent(GlLink)
        .element.dispatchEvent(
          new MouseEvent('click', { bubbles: true, cancelable: true, ...init }),
        );
      wrapper.element.removeEventListener('click', stopNavigation);

      return preventedByCard;
    };

    const createConnected = (provide = { openGovernancePanel }) =>
      createComponent({
        props: { agentClass: 'EXTERNAL' },
        provide,
        connectedHandler: jest
          .fn()
          .mockResolvedValue(connectedAgentsResponse([connectedAgentNode('claude-code')])),
      });

    beforeEach(() => {
      openGovernancePanel = jest.fn();
    });

    it("opens the agent's sessions in the panel instead of following the link", async () => {
      createConnected();
      await waitForPromises();

      expect(clickRow()).toBe(true);
      expect(openGovernancePanel).toHaveBeenCalledWith('audit-events', {
        filters: {
          agentType: 'claude-code',
          agentClass: 'EXTERNAL',
          startTimeAfter: '2026-09-19',
        },
        title: 'Claude Code',
      });
    });

    it('follows the link when there is no panel to open, as with the flag off', async () => {
      createConnected({});
      await waitForPromises();

      expect(clickRow()).toBe(false);
    });

    it.each(['ctrlKey', 'metaKey', 'shiftKey'])(
      'follows the link on a click with %s, to open the tab elsewhere',
      async (key) => {
        createConnected();
        await waitForPromises();

        expect(clickRow({ [key]: true })).toBe(false);
        expect(openGovernancePanel).not.toHaveBeenCalled();
      },
    );

    it('keeps the agent page link for a catalog agent', async () => {
      createComponent({
        provide: { openGovernancePanel },
        handler: jest
          .fn()
          .mockResolvedValue(configuredItemsResponse([consumerNode(7, 'Release agent')])),
      });
      await waitForPromises();

      expect(clickRow()).toBe(false);
      expect(openGovernancePanel).not.toHaveBeenCalled();
    });
  });

  it('states the fixed 30-day usage window it ranks on', async () => {
    createComponent();
    await waitForPromises();

    expect(wrapper.findByTestId('card-footnote').text()).toBe(
      'Usage rankings are always based on the last 30 days.',
    );
  });

  describe('tracking', () => {
    const { bindInternalEventDocument } = useMockInternalEventsTracking();
    const CARD_LINK_EVENT = 'click_card_link_on_ai_governance_dashboard';

    beforeEach(async () => {
      createComponent({
        handler: jest
          .fn()
          .mockResolvedValue(configuredItemsResponse([consumerNode(7, 'Release agent')])),
        connectedHandler: jest
          .fn()
          .mockResolvedValue(connectedAgentsResponse([connectedAgentNode('claude-code')])),
      });
      await waitForPromises();
    });

    it('marks a linked catalog agent row as a card link click on the agent inventory card', () => {
      expect(findRows().at(1).findComponent(GlLink).attributes()).toMatchObject({
        'data-event-tracking': CARD_LINK_EVENT,
        'data-event-label': 'agent_inventory',
        'data-event-property': 'row',
      });
    });

    it('marks a linked connected agent row as a card link click on the agent inventory card', () => {
      expect(findRows().at(0).findComponent(GlLink).attributes()).toMatchObject({
        'data-event-tracking': CARD_LINK_EVENT,
        'data-event-label': 'agent_inventory',
        'data-event-property': 'row',
      });
    });

    it('marks the view-all link as a card link click on the agent inventory card', () => {
      expect(findViewAllLink().attributes()).toMatchObject({
        'data-event-tracking': CARD_LINK_EVENT,
        'data-event-label': 'agent_inventory',
        'data-event-property': 'view_all',
      });
    });

    it('tracks a click on a linked row', () => {
      const { triggerEvent, trackEventSpy } = bindInternalEventDocument(wrapper.element);

      triggerEvent(findRows().at(1).findComponent(GlLink).element);

      expect(trackEventSpy).toHaveBeenCalledWith(CARD_LINK_EVENT, {
        label: 'agent_inventory',
        property: 'row',
      });
    });
  });
});
