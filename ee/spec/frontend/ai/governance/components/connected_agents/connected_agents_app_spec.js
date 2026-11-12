import Vue from 'vue';
import VueApollo from 'vue-apollo';
import { GlAlert, GlFilteredSearch, GlIcon, GlKeysetPagination } from '@gitlab/ui';
import { mountExtended } from 'helpers/vue_test_utils_helper';
import createMockApollo from 'helpers/mock_apollo_helper';
import waitForPromises from 'helpers/wait_for_promises';
import ConnectedAgentsApp from 'ee/ai/governance/components/connected_agents/connected_agents_app.vue';
import getAiAgentIdentitiesQuery from 'ee/ai/governance/graphql/queries/get_ai_agent_identities.query.graphql';

Vue.use(VueApollo);

const GROUP_FULL_PATH = 'gitlab-org';
const PROJECT_FULL_PATH = 'gitlab-org/gitlab';

const mockPageInfo = {
  hasNextPage: true,
  hasPreviousPage: false,
  startCursor: 'cursor-start',
  endCursor: 'cursor-end',
  __typename: 'PageInfo',
};

const identity = ({
  id,
  agentType = 'CLAUDE_CODE',
  lastSyncedAt = '2026-11-01T10:00:00Z',
  status = 'ACTIVE',
  sessionCount = 3,
}) => ({
  id: `gid://gitlab/Ai::ExternalAgents::AgentIdentity/${id}`,
  agentType,
  user: {
    id: 'gid://gitlab/User/1',
    name: 'Ada Lovelace',
    username: 'ada',
    avatarUrl: 'https://example.com/ada.png',
    webPath: '/ada',
    __typename: 'UserCore',
  },
  project: {
    id: 'gid://gitlab/Project/1',
    nameWithNamespace: 'GitLab.org / GitLab',
    webPath: '/gitlab-org/gitlab',
    __typename: 'Project',
  },
  createdAt: '2026-10-01T10:00:00Z',
  lastSyncedAt,
  status,
  sessionCount,
  __typename: 'AiAgentIdentity',
});

const mockIdentities = {
  nodes: [
    identity({ id: 1 }),
    identity({
      id: 2,
      agentType: 'CODEX',
      lastSyncedAt: null,
      status: 'INACTIVE',
      sessionCount: 0,
    }),
    identity({ id: 3, agentType: 'OPENCODE', status: 'REVOKED', sessionCount: 1001 }),
  ],
  pageInfo: mockPageInfo,
  __typename: 'AiAgentIdentityConnection',
};

const mockResponse = ({ isProject = false, identities = mockIdentities } = {}) => {
  const container = isProject
    ? {
        project: {
          id: 'gid://gitlab/Project/1',
          aiAgentIdentities: identities,
          __typename: 'Project',
        },
      }
    : { group: { id: 'gid://gitlab/Group/1', aiAgentIdentities: identities, __typename: 'Group' } };
  return { data: container };
};

describe('ConnectedAgentsApp', () => {
  let wrapper;
  let queryHandler;

  const createComponent = ({
    handler = jest.fn().mockResolvedValue(mockResponse()),
    provide = { groupFullPath: GROUP_FULL_PATH, projectFullPath: '' },
  } = {}) => {
    queryHandler = handler;

    wrapper = mountExtended(ConnectedAgentsApp, {
      apolloProvider: createMockApollo([[getAiAgentIdentitiesQuery, queryHandler]]),
      provide,
    });
  };

  const findRows = () => wrapper.findAllByTestId('connected-agent-row');
  const findAgentNames = () =>
    wrapper.findAllByTestId('connected-agent-name').wrappers.map((w) => w.text());
  const findStatuses = () =>
    wrapper.findAllByTestId('connected-agent-status').wrappers.map((w) => w.text());
  const findSessionCounts = () =>
    wrapper.findAllByTestId('connected-agent-session-count').wrappers.map((w) => w.text());
  const findFilteredSearch = () => wrapper.findComponent(GlFilteredSearch);
  const findPagination = () => wrapper.findComponent(GlKeysetPagination);

  describe('on a group', () => {
    beforeEach(async () => {
      createComponent();
      await waitForPromises();
    });

    it('queries the group identities', () => {
      expect(queryHandler).toHaveBeenCalledWith(
        expect.objectContaining({
          groupFullPath: GROUP_FULL_PATH,
          isProject: false,
          first: 20,
          after: null,
        }),
      );
    });

    it('renders a row for each agent identity', () => {
      expect(findRows()).toHaveLength(3);
    });

    it('names each agent by its product name', () => {
      expect(findAgentNames()).toEqual(['Claude Code', 'Codex', 'OpenCode']);
    });

    it('shows the approved logo next to the agent name, and the connected icon for agents without one', () => {
      const logo = findRows().at(1).find('[data-testid="connected-agent-logo"]');

      expect(logo.element.src).toBe('file-mock-codex.svg');
      expect(logo.classes('gl-scale-150')).toBe(true);
      expect(findRows().at(1).findComponent(GlIcon).exists()).toBe(false);

      [0, 2].forEach((index) => {
        const row = findRows().at(index);

        expect(row.find('[data-testid="connected-agent-logo"]').exists()).toBe(false);
        expect(row.findComponent(GlIcon).props('name')).toBe('connected');
      });
    });

    it('renders the user who connected the agent and its project', () => {
      expect(wrapper.findAllByTestId('connected-agent-user').at(0).attributes('href')).toBe('/ada');
      expect(wrapper.findAllByTestId('connected-agent-project').at(0).text()).toBe(
        'GitLab.org / GitLab',
      );
    });

    it('renders the status of each identity', () => {
      expect(findStatuses()).toEqual(['Active', 'Inactive', 'Revoked']);
    });

    it('shows when an agent has never synced', () => {
      expect(wrapper.findAllByTestId('connected-agent-never-synced')).toHaveLength(1);
    });

    it('shows the session count, capped at the limit', () => {
      expect(findSessionCounts()).toEqual(['3', '0', '1,000+']);
    });

    it('offers agent, user and status filters with the GraphQL values', () => {
      const [agent, user, status] = findFilteredSearch().props('availableTokens');

      expect(agent.options.map(({ value }) => value)).toEqual([
        'CLAUDE_CODE',
        'CURSOR',
        'OPENCODE',
        'CODEX',
      ]);
      expect(user).toMatchObject({
        type: 'userId',
        valueField: 'id',
        fullPath: GROUP_FULL_PATH,
        isProject: false,
      });
      expect(status.options.map(({ value }) => value)).toEqual(['ACTIVE', 'INACTIVE', 'REVOKED']);
    });

    it('requests the previous page', async () => {
      findPagination().vm.$emit('prev', 'cursor-start');
      await waitForPromises();

      expect(queryHandler).toHaveBeenLastCalledWith(
        expect.objectContaining({ before: 'cursor-start', last: 20, after: null, first: null }),
      );
    });

    it('requests the next page', async () => {
      findPagination().vm.$emit('next', 'cursor-end');
      await waitForPromises();

      expect(queryHandler).toHaveBeenLastCalledWith(
        expect.objectContaining({ after: 'cursor-end', first: 20, before: null, last: null }),
      );
    });
  });

  describe('on a project', () => {
    beforeEach(async () => {
      createComponent({
        handler: jest.fn().mockResolvedValue(mockResponse({ isProject: true })),
        provide: { groupFullPath: GROUP_FULL_PATH, projectFullPath: PROJECT_FULL_PATH },
      });
      await waitForPromises();
    });

    it('queries the project identities', () => {
      expect(queryHandler).toHaveBeenCalledWith(
        expect.objectContaining({ projectFullPath: PROJECT_FULL_PATH, isProject: true }),
      );
    });

    it('renders the identities without a project column', () => {
      expect(findRows()).toHaveLength(3);
      expect(wrapper.findAllByTestId('connected-agent-project')).toHaveLength(0);
      expect(wrapper.find('thead').text()).not.toContain('Project');
    });

    it('searches users of the project', () => {
      const user = findFilteredSearch()
        .props('availableTokens')
        .find(({ type }) => type === 'userId');

      expect(user).toMatchObject({ fullPath: PROJECT_FULL_PATH, isProject: true });
    });
  });

  describe('filtering', () => {
    beforeEach(async () => {
      createComponent();
      await waitForPromises();
    });

    it('passes the filters to the query and starts from the first page', async () => {
      findPagination().vm.$emit('next', 'cursor-end');
      await waitForPromises();

      findFilteredSearch().vm.$emit('submit', [
        { type: 'agentType', value: { data: 'CODEX', operator: '=' } },
        { type: 'userId', value: { data: 'gid://gitlab/User/1', operator: '=' } },
        { type: 'status', value: { data: 'ACTIVE', operator: '=' } },
        'free text',
      ]);
      await waitForPromises();

      expect(queryHandler).toHaveBeenLastCalledWith(
        expect.objectContaining({
          agentTypes: ['CODEX'],
          userId: 'gid://gitlab/User/1',
          status: 'ACTIVE',
          after: null,
        }),
      );
    });
  });

  describe('clearing the filters', () => {
    beforeEach(async () => {
      const revokedOnly = { ...mockIdentities, nodes: [mockIdentities.nodes[2]] };
      createComponent({
        handler: jest
          .fn()
          .mockImplementation(({ status }) =>
            Promise.resolve(mockResponse({ identities: status ? revokedOnly : mockIdentities })),
          ),
      });
      await waitForPromises();
    });

    it('lists every identity again', async () => {
      findFilteredSearch().vm.$emit('submit', [
        { type: 'status', value: { data: 'REVOKED', operator: '=' } },
      ]);
      await waitForPromises();
      expect(findRows()).toHaveLength(1);

      findFilteredSearch().vm.$emit('clear');
      await waitForPromises();
      expect(findRows()).toHaveLength(3);
    });
  });

  describe('when the query fails', () => {
    beforeEach(async () => {
      createComponent({ handler: jest.fn().mockRejectedValue(new Error('failed')) });
      await waitForPromises();
    });

    it('shows an error', () => {
      expect(wrapper.findComponent(GlAlert).text()).toBe('Failed to load connected agents.');
    });
  });

  describe('when there are no identities', () => {
    beforeEach(async () => {
      createComponent({
        handler: jest.fn().mockResolvedValue(
          mockResponse({
            identities: {
              nodes: [],
              pageInfo: { ...mockPageInfo, hasNextPage: false },
              __typename: 'AiAgentIdentityConnection',
            },
          }),
        ),
      });
      await waitForPromises();
    });

    it('shows the empty state without pagination', () => {
      expect(wrapper.findByTestId('connected-agents-empty').text()).toBe(
        'No connected agents found.',
      );
      expect(findPagination().exists()).toBe(false);
    });
  });
});
