import Vue from 'vue';
import VueApollo from 'vue-apollo';
import createMockApollo from 'helpers/mock_apollo_helper';
import { shallowMountExtended } from 'helpers/vue_test_utils_helper';
import { stubComponent } from 'helpers/stub_component';
import waitForPromises from 'helpers/wait_for_promises';
import AgentActorLine from 'ee/ai/shared/widgets/agent_actor_line.vue';
import WorkItemAgentPresence from 'ee/work_items/components/work_item_agent_presence.vue';
import workItemAgentPresenceQuery from 'ee/work_items/graphql/work_item_agent_presence.query.graphql';
import { mockAgentPresence } from 'ee_jest/ai/shared/widgets/mock_data';

Vue.use(VueApollo);

describe('WorkItemAgentPresence', () => {
  let wrapper;
  let queryHandler;

  const fullPath = 'group/project';
  const workItemIid = '1';

  const findAgentActorLine = () => wrapper.findComponent(AgentActorLine);
  const findActorLineSeparator = () => wrapper.findByTestId('actor-line-separator');

  const agentPresenceResponse = (agentPresence) => ({
    data: {
      namespace: {
        __typename: 'Namespace',
        id: 'gid://gitlab/Namespaces::ProjectNamespace/1',
        workItem: {
          __typename: 'WorkItem',
          id: 'gid://gitlab/WorkItem/1',
          agentPresence: agentPresence && {
            __typename: 'DuoWorkflowAgentPresence',
            ...agentPresence,
            user: agentPresence.user && { __typename: 'UserCore', ...agentPresence.user },
            userPermissions: {
              __typename: 'DuoWorkflowAgentPresencePermissions',
              ...agentPresence.userPermissions,
            },
          },
        },
      },
    },
  });

  const createComponent = async ({
    agentPresence = mockAgentPresence,
    agentPresenceConsolidation = true,
    props = {},
  } = {}) => {
    queryHandler = jest.fn().mockResolvedValue(agentPresenceResponse(agentPresence));

    wrapper = shallowMountExtended(WorkItemAgentPresence, {
      apolloProvider: createMockApollo([[workItemAgentPresenceQuery, queryHandler]]),
      propsData: { fullPath, workItemIid, ...props },
      provide: { glFeatures: { agentPresenceConsolidation } },
      stubs: { AgentActorLine: stubComponent(AgentActorLine) },
    });

    await waitForPromises();
  };

  describe('when the agentPresenceConsolidation feature flag is disabled', () => {
    beforeEach(() => createComponent({ agentPresenceConsolidation: false }));

    it('does not request the agent presence', () => {
      expect(queryHandler).not.toHaveBeenCalled();
    });

    it('renders no actor line and no separator', () => {
      expect(findAgentActorLine().exists()).toBe(false);
      expect(findActorLineSeparator().exists()).toBe(false);
    });
  });

  describe('when there is no work item iid', () => {
    beforeEach(() => createComponent({ props: { workItemIid: null } }));

    it('does not request the agent presence', () => {
      expect(queryHandler).not.toHaveBeenCalled();
    });
  });

  describe.each`
    description            | agentPresence
    ${'is null'}           | ${null}
    ${'has no agent name'} | ${{ ...mockAgentPresence, agentName: null }}
  `('when the agent presence $description', ({ agentPresence }) => {
    beforeEach(() => createComponent({ agentPresence }));

    it('renders no actor line and no separator', () => {
      expect(findAgentActorLine().exists()).toBe(false);
      expect(findActorLineSeparator().exists()).toBe(false);
    });
  });

  describe('when the agent presence is complete', () => {
    beforeEach(() => createComponent());

    it('requests the agent presence for the work item', () => {
      expect(queryHandler).toHaveBeenCalledWith({ fullPath, iid: workItemIid });
    });

    it('renders the actor line with every prop mapped', () => {
      expect(findAgentActorLine().props()).toEqual({
        agentName: mockAgentPresence.agentName,
        agentCatalogPath: mockAgentPresence.agentCatalogWebPath,
        sessionId: mockAgentPresence.sessionId,
        user: expect.objectContaining(mockAgentPresence.user),
        triggerSource: mockAgentPresence.triggerSource,
        canViewSession: true,
        withAgentName: true,
        withInitiator: true,
      });
    });

    it('renders the separator before the actor line', () => {
      expect(findActorLineSeparator().text()).toBe('·');
    });
  });

  describe('when the user cannot read the Duo workflow', () => {
    beforeEach(() =>
      createComponent({
        agentPresence: { ...mockAgentPresence, userPermissions: { readDuoWorkflow: false } },
      }),
    );

    it('passes canViewSession as false', () => {
      expect(findAgentActorLine().props('canViewSession')).toBe(false);
    });
  });
});
