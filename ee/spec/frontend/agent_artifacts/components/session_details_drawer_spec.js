import Vue, { nextTick } from 'vue';
import VueApollo from 'vue-apollo';
import { GlAttributeList, GlButton } from '@gitlab/ui';
import { shallowMountExtended } from 'helpers/vue_test_utils_helper';
import createMockApollo from 'helpers/mock_apollo_helper';
import waitForPromises from 'helpers/wait_for_promises';
import * as Sentry from '~/sentry/sentry_browser_wrapper';
import SessionDetailsDrawer from 'ee/agent_artifacts/components/session_details_drawer.vue';
import SessionDetailsBody from 'ee/agent_artifacts/components/session_details_body.vue';
import SessionAuditEventsList from 'ee/agent_artifacts/components/session_audit_events_list.vue';
import SessionLinkedItems from 'ee/agent_artifacts/components/session_linked_items.vue';
import AuditEventDetailsPanel from 'ee/agent_artifacts/components/audit_event_details_panel.vue';
import CrudComponent from '~/vue_shared/components/crud_component.vue';
import DynamicPanel from '~/vue_shared/components/dynamic_panel.vue';
import { formatAgentDefinition } from 'ee/ai/duo_agents_platform/utils';
import getProjectSessionAuditEventsQuery from 'ee/agent_artifacts/graphql/queries/get_project_session_audit_events.query.graphql';
import getProjectAiGovernanceSessionAuditEventsQuery from 'ee/agent_artifacts/graphql/queries/get_project_ai_governance_session_audit_events.query.graphql';
import getGroupAiGovernanceSessionAuditEventsQuery from 'ee/agent_artifacts/graphql/queries/get_group_ai_governance_session_audit_events.query.graphql';
import getProjectAiGovernanceSessionLinksQuery from 'ee/agent_artifacts/graphql/queries/get_project_ai_governance_session_links.query.graphql';
import getGroupAiGovernanceSessionLinksQuery from 'ee/agent_artifacts/graphql/queries/get_group_ai_governance_session_links.query.graphql';
import {
  buildLinkConnection,
  buildSessionLinksResponse,
  mockGroupedSessionLinks,
} from '../mock_data';

Vue.use(VueApollo);

jest.mock('~/sentry/sentry_browser_wrapper');
jest.mock('ee/ai/duo_agents_platform/utils', () => ({
  formatAgentDefinition: jest.fn((name) => name),
}));

describe('SessionDetailsDrawer', () => {
  let wrapper;

  const mockActiveItem = {
    id: 'gid://gitlab/Ai::DuoWorkflows::Workflow/1908',
    sessionId: '1908',
    flowType: 'false_positive_detection/v1',
    sessionStartedAt: '2024-01-01T12:00:00Z',
    webPath: '/gitlab-org/security-scanner/-/automate/agent-sessions/1908',
    downloadPath: '/gitlab-org/security-scanner/-/security/agent_artifacts/1908/download',
    project: {
      name: 'security-scanner',
      webPath: '/gitlab-org/security-scanner',
    },
  };

  const PROJECT_FULL_PATH = 'gitlab-org/security-scanner';

  const buildEvent = (id) => ({
    id,
    eventName: 'tool_execution',
    createdAt: '2026-05-04T10:30:00Z',
    details: {},
    ipAddress: '127.0.0.1',
    workflowId: '1908',
    author: null,
    humanAuthor: null,
    __typename: 'AiAuditEvent',
  });

  const pageOneEvents = [buildEvent('event-1'), buildEvent('event-2')];
  const pageTwoEvents = [buildEvent('event-3'), buildEvent('event-4')];

  const buildResponse = ({ nodes, hasNextPage, hasPreviousPage }) => ({
    data: {
      project: {
        id: 'gid://gitlab/Project/1',
        duoWorkflowSessionArtifacts: {
          nodes: [
            {
              id: mockActiveItem.id,
              auditEvents: {
                nodes,
                pageInfo: {
                  hasNextPage,
                  hasPreviousPage,
                  startCursor: nodes[0]?.id ?? null,
                  endCursor: nodes[nodes.length - 1]?.id ?? null,
                  __typename: 'PageInfo',
                },
                __typename: 'AiAuditEventConnection',
              },
              __typename: 'DuoWorkflowSessionArtifact',
            },
          ],
          __typename: 'DuoWorkflowSessionArtifactConnection',
        },
        __typename: 'Project',
      },
    },
  });

  const pageOneResponse = buildResponse({
    nodes: pageOneEvents,
    hasNextPage: true,
    hasPreviousPage: false,
  });

  const pageTwoResponse = buildResponse({
    nodes: pageTwoEvents,
    hasNextPage: false,
    hasPreviousPage: true,
  });

  const notFoundResponse = {
    data: {
      project: {
        id: 'gid://gitlab/Project/1',
        duoWorkflowSessionArtifacts: {
          nodes: [],
          __typename: 'DuoWorkflowSessionArtifactConnection',
        },
        __typename: 'Project',
      },
    },
  };

  const createComponent = ({
    props = {},
    handler = jest.fn().mockResolvedValue(pageOneResponse),
    mount = shallowMountExtended,
    provide = {},
    slots = {},
  } = {}) => {
    const apolloProvider = createMockApollo([[getProjectSessionAuditEventsQuery, handler]]);

    wrapper = mount(SessionDetailsDrawer, {
      apolloProvider,
      provide: {
        projectFullPath: PROJECT_FULL_PATH,
        groupFullPath: null,
        ...provide,
      },
      propsData: {
        activeItem: mockActiveItem,
        ...props,
      },
      slots,
      stubs: {
        MountingPortal: { template: '<div><slot /></div>' },
        DynamicPanel: {
          template: '<div><slot name="header" /><slot /></div>',
          props: ['maximizeUrl'],
          emits: ['close'],
        },
        SessionDetailsBody,
        SessionAuditEventsList,
        CrudComponent,
        GlAttributeList,
        GlButton,
      },
    });

    return handler;
  };

  const findDrawer = () => wrapper.findByTestId('session-details-drawer');
  const findDynamicPanel = () => wrapper.findComponent(DynamicPanel);
  const findDrawerContentTitle = () => wrapper.findByTestId('session-content-title');
  const findCrudComponent = () => wrapper.findComponent(CrudComponent);
  const findViewFullSessionButton = () => wrapper.findByTestId('view-full-session-details-button');
  const findSessionLink = () => wrapper.findByTestId('session-link');
  const findFormattedDate = () => wrapper.findByTestId('formatted-date');
  const findProjectLink = () => wrapper.findByTestId('project-link');
  const findSessionDetailsBody = () => wrapper.findComponent(SessionDetailsBody);
  const findAuditEventPanel = () => wrapper.findComponent(AuditEventDetailsPanel);
  const findBackButton = () => wrapper.findComponentByTestId('audit-event-back-button');
  const findSessionBackButton = () => wrapper.findComponentByTestId('session-back-button');
  const findPrevButton = () => wrapper.findComponentByTestId('audit-event-prev-button');
  const findNextButton = () => wrapper.findComponentByTestId('audit-event-next-button');

  describe('in the dashboard side panel', () => {
    beforeEach(() => {
      createComponent({
        props: { maximizeUrl: '?tab=agent-artifacts&session=5', panelLayout: true },
        slots: { actions: '<button data-testid="extra-action">Revoke</button>' },
      });
    });

    it('gives the panel its full page link', () => {
      expect(findDynamicPanel().props('maximizeUrl')).toBe('?tab=agent-artifacts&session=5');
    });

    it('uses the panel layout and passes its actions through', () => {
      expect(findSessionDetailsBody().props('panelLayout')).toBe(true);
      expect(wrapper.findByTestId('extra-action').exists()).toBe(true);
    });
  });

  it('has no full page link or panel layout on the Audit events tab', () => {
    createComponent();

    expect(findDynamicPanel().props('maximizeUrl')).toBe(null);
    expect(findSessionDetailsBody().props('panelLayout')).toBe(false);
  });

  describe('with a back label', () => {
    beforeEach(() => {
      createComponent({ props: { backLabel: 'Audit events' } });
    });

    it('shows a back button to the panel it replaced while viewing the session', () => {
      expect(findSessionBackButton().text()).toBe('Audit events');
      expect(findPrevButton().exists()).toBe(false);
      expect(findNextButton().exists()).toBe(false);
    });

    it('emits back when the back button is clicked', async () => {
      await findSessionBackButton().vm.$emit('click');

      expect(wrapper.emitted('back')).toHaveLength(1);
    });

    it('moves focus into the panel when a parent asks', () => {
      const focus = jest.spyOn(findDynamicPanel().element, 'focus');

      wrapper.vm.focus();

      expect(focus).toHaveBeenCalled();
    });

    it('swaps it for the event controls while an audit event is open', async () => {
      await wrapper.setProps({ selectedEvent: { id: 'gid://gitlab/AuditEvent/1' } });

      expect(findSessionBackButton().exists()).toBe(false);
      expect(findBackButton().exists()).toBe(true);
    });
  });

  describe('basic rendering (shallow, no query)', () => {
    beforeEach(() => {
      createComponent();
    });

    it('renders the drawer', () => {
      expect(findDrawer().exists()).toBe(true);
    });

    it('displays formatted agent name in content', () => {
      expect(findDrawerContentTitle().text()).toBe(formatAgentDefinition(mockActiveItem.flowType));
    });

    it('does not render the event navigation controls while viewing the session', () => {
      expect(findBackButton().exists()).toBe(false);
      expect(findPrevButton().exists()).toBe(false);
      expect(findNextButton().exists()).toBe(false);
    });

    it('does not render a back button to another panel by default', () => {
      expect(findSessionBackButton().exists()).toBe(false);
    });

    it('emits close event when DynamicPanel emits close', async () => {
      await findDynamicPanel().vm.$emit('close');

      expect(wrapper.emitted('close')).toHaveLength(1);
    });

    describe('keyboard navigation', () => {
      it('emits close event when Escape key is pressed', () => {
        const event = new KeyboardEvent('keydown', { key: 'Escape' });
        document.dispatchEvent(event);

        expect(wrapper.emitted('close')).toHaveLength(1);
      });

      it('does not emit close event when other keys are pressed', () => {
        const event = new KeyboardEvent('keydown', { key: 'Enter' });
        document.dispatchEvent(event);

        expect(wrapper.emitted('close')).toBeUndefined();
      });
    });

    describe('event listener cleanup', () => {
      it('removes keydown event listener on destroy', () => {
        const removeEventListenerSpy = jest.spyOn(document, 'removeEventListener');

        wrapper.destroy();

        expect(removeEventListenerSpy).toHaveBeenCalledWith('keydown', wrapper.vm.closeOnEscape);
      });
    });

    describe('session details body', () => {
      it('renders the SessionDetailsBody and passes through the session id', () => {
        expect(findSessionDetailsBody().exists()).toBe(true);
        expect(findSessionDetailsBody().props('sessionId')).toBe(mockActiveItem.id);
      });

      it('passes a null session id through when the active item has none', () => {
        createComponent({ props: { activeItem: { ...mockActiveItem, id: null } } });

        expect(findSessionDetailsBody().props('sessionId')).toBe(null);
      });

      it('forwards the body select event as its own select', () => {
        findSessionDetailsBody().vm.$emit('select', { id: 'event-1' });

        expect(wrapper.emitted('select')).toEqual([[{ id: 'event-1' }]]);
      });
    });

    describe('when an audit event is selected', () => {
      const mockEvent = { id: 'event-1', eventName: 'ai_agent_session_ended', details: {} };

      beforeEach(() => {
        createComponent({
          props: { selectedEvent: mockEvent },
        });
      });

      it('renders the audit event details panel instead of the session body', () => {
        expect(findAuditEventPanel().exists()).toBe(true);
        expect(findSessionDetailsBody().exists()).toBe(false);
      });

      it('passes the session target facts to the details panel', () => {
        expect(findAuditEventPanel().props()).toMatchObject({
          flowName: mockActiveItem.flowType,
          sessionId: '1908',
          source: null,
        });
      });

      it('names an external session without a flow type by its source label', () => {
        createComponent({
          props: {
            activeItem: {
              ...mockActiveItem,
              flowType: null,
              sessionId: 'abc-123',
              source: 'CLAUDE_CODE_GLAB',
            },
            selectedEvent: mockEvent,
          },
        });

        expect(findAuditEventPanel().props()).toMatchObject({
          flowName: 'Claude Code (glab)',
          sessionId: 'abc-123',
          source: 'CLAUDE_CODE_GLAB',
        });
      });

      it.each([
        ['cursor', 'Cursor (glab)'],
        ['codex', 'Codex (glab)'],
        ['claude-code', 'Claude Code (glab)'],
        [null, 'Claude Code (glab)'],
      ])('names a glab session with the %s agent type after its agent', (agentType, label) => {
        createComponent({
          props: {
            activeItem: {
              ...mockActiveItem,
              flowType: null,
              source: 'CLAUDE_CODE_GLAB',
              agentType,
            },
            selectedEvent: mockEvent,
          },
        });

        expect(findAuditEventPanel().props('flowName')).toBe(label);
      });

      it('emits close when DynamicPanel emits close', async () => {
        await findDynamicPanel().vm.$emit('close');

        expect(wrapper.emitted('close')).toHaveLength(1);
      });

      it('renders the back and prev/next controls in the chrome', () => {
        expect(findBackButton().exists()).toBe(true);
        expect(findPrevButton().exists()).toBe(true);
        expect(findNextButton().exists()).toBe(true);
      });

      it('emits back when the back button is clicked', () => {
        findBackButton().vm.$emit('click');

        expect(wrapper.emitted('back')).toHaveLength(1);
      });

      it('renders the download button with the active item download path', () => {
        expect(wrapper.findByTestId('download-audit-artifact-button').exists()).toBe(true);
        expect(wrapper.findByTestId('download-audit-artifact-button').attributes('href')).toBe(
          mockActiveItem.downloadPath,
        );
      });

      it('does not render the download button when the active item has no download path', () => {
        createComponent({
          props: {
            activeItem: { ...mockActiveItem, downloadPath: null },
            selectedEvent: mockEvent,
          },
        });

        expect(wrapper.findByTestId('download-audit-artifact-button').exists()).toBe(false);
      });
    });

    describe('session details section', () => {
      it('renders CrudComponent', () => {
        expect(findCrudComponent().exists()).toBe(true);
      });

      it('renders view full session details button in actions slot', () => {
        expect(findViewFullSessionButton().exists()).toBe(true);
        expect(findViewFullSessionButton().text()).toBe('View full session details');
        expect(findViewFullSessionButton().attributes('href')).toBe(mockActiveItem.webPath);
      });

      it('renders session row with session link', () => {
        expect(findSessionLink().attributes('href')).toBe(mockActiveItem.webPath);
        expect(findSessionLink().text()).toBe('#1908');
      });

      it('renders date row with formatted date', () => {
        expect(findFormattedDate().text()).toBe('2024-01-01 12:00:00 UTC');
      });

      it('renders project row with project link', () => {
        expect(findProjectLink().attributes('href')).toBe(mockActiveItem.project.webPath);
      });

      it('renders project row with a hyphen placeholder when project is not present', () => {
        createComponent({
          props: {
            activeItem: {
              ...mockActiveItem,
              project: null,
            },
          },
        });

        expect(findProjectLink().exists()).toBe(false);
        expect(wrapper.findByTestId('project-empty').text()).toBe('—');
      });
    });
  });

  describe('audit events query and navigation', () => {
    describe('crossing a page boundary going forward', () => {
      let handler;

      beforeEach(async () => {
        handler = jest
          .fn()
          .mockResolvedValueOnce(pageOneResponse)
          .mockResolvedValueOnce(pageTwoResponse);

        createComponent({ props: { selectedEvent: pageOneEvents[1] }, handler });
        await waitForPromises();
      });

      it('fetches the next page using the current endCursor', async () => {
        wrapper.vm.goToNext();
        await waitForPromises();

        expect(handler).toHaveBeenCalledTimes(2);
        expect(handler).toHaveBeenLastCalledWith(
          expect.objectContaining({ after: pageOneEvents[1].id, before: null }),
        );
      });

      it('auto-selects the first event of the newly loaded page', async () => {
        wrapper.vm.goToNext();
        await waitForPromises();

        expect(wrapper.emitted('select')).toEqual([[pageTwoEvents[0]]]);
      });

      it('disables both buttons while the fetch is in flight', async () => {
        wrapper.vm.goToNext();
        await nextTick();

        expect(wrapper.vm.hasPrevEvent).toBe(false);
        expect(wrapper.vm.hasNextEvent).toBe(false);

        await waitForPromises();
      });
    });

    describe('crossing a page boundary going backward', () => {
      let handler;

      beforeEach(async () => {
        handler = jest
          .fn()
          .mockResolvedValueOnce(pageTwoResponse)
          .mockResolvedValueOnce(pageOneResponse);

        createComponent({ props: { selectedEvent: pageTwoEvents[0] }, handler });
        await waitForPromises();
      });

      it('fetches the previous page using the current startCursor', async () => {
        wrapper.vm.goToPrevious();
        await waitForPromises();

        expect(handler).toHaveBeenCalledTimes(2);
        expect(handler).toHaveBeenLastCalledWith(
          expect.objectContaining({ before: pageTwoEvents[0].id, after: null }),
        );
      });

      it('auto-selects the last event of the newly loaded page', async () => {
        wrapper.vm.goToPrevious();
        await waitForPromises();

        expect(wrapper.emitted('select')).toEqual([[pageOneEvents[1]]]);
      });
    });

    describe('when there are no more pages', () => {
      it('does not fetch or emit select when goToNext is called at the last event with no next page', async () => {
        const handler = jest.fn().mockResolvedValue(pageTwoResponse);
        createComponent({ props: { selectedEvent: pageTwoEvents[1] }, handler });
        await waitForPromises();

        wrapper.vm.goToNext();
        await waitForPromises();

        expect(handler).toHaveBeenCalledTimes(1);
        expect(wrapper.emitted('select')).toBeUndefined();
      });

      it('does not fetch or emit select when goToPrevious is called at the first event with no previous page', async () => {
        const handler = jest.fn().mockResolvedValue(pageOneResponse);
        createComponent({ props: { selectedEvent: pageOneEvents[0] }, handler });
        await waitForPromises();

        wrapper.vm.goToPrevious();
        await waitForPromises();

        expect(handler).toHaveBeenCalledTimes(1);
        expect(wrapper.emitted('select')).toBeUndefined();
      });
    });

    describe('when neither groupFullPath nor projectFullPath is provided', () => {
      it('skips the query', async () => {
        const handler = jest.fn().mockResolvedValue(pageOneResponse);
        createComponent({ handler, provide: { projectFullPath: null } });
        await waitForPromises();

        expect(handler).not.toHaveBeenCalled();
      });
    });

    describe('when the workflow is not found', () => {
      it('shows the error alert instead of the empty state', async () => {
        const handler = jest.fn().mockResolvedValue(notFoundResponse);
        createComponent({ handler });
        await waitForPromises();

        expect(wrapper.text()).toContain('Failed to load audit events.');
        expect(wrapper.findByTestId('empty-state').exists()).toBe(false);
      });
    });

    describe('when the active session changes', () => {
      const OTHER_SESSION_ID = 'gid://gitlab/Ai::DuoWorkflows::Workflow/2909';

      const pageToSecondPage = async (handler) => {
        createComponent({ handler });
        await waitForPromises();

        wrapper.vm.handleNext(pageOneEvents[1].id);
        await waitForPromises();

        expect(handler).toHaveBeenLastCalledWith(
          expect.objectContaining({ after: pageOneEvents[1].id }),
        );
      };

      it('queries the new session from the first page instead of reusing the old cursor', async () => {
        const handler = jest.fn().mockResolvedValue(pageOneResponse);
        await pageToSecondPage(handler);

        await wrapper.setProps({
          activeItem: { ...mockActiveItem, id: OTHER_SESSION_ID },
        });
        await waitForPromises();

        expect(handler).toHaveBeenLastCalledWith(
          expect.objectContaining({
            workflowId: OTHER_SESSION_ID,
            after: null,
            before: null,
          }),
        );
      });

      it('does not auto-select an event when a boundary fetch is abandoned mid-flight', async () => {
        const handler = jest.fn().mockResolvedValue(pageOneResponse);
        createComponent({ props: { selectedEvent: pageOneEvents[1] }, handler });
        await waitForPromises();

        // Start a boundary fetch, then switch sessions before it settles. The
        // pending auto-select must not carry over and pick an event in the new
        // session on the user's behalf.
        wrapper.vm.goToNext();
        expect(wrapper.vm.isFetchingBoundary).toBe(true);

        await wrapper.setProps({
          activeItem: { ...mockActiveItem, id: OTHER_SESSION_ID },
        });
        await waitForPromises();

        expect(wrapper.emitted('select')).toBeUndefined();
      });

      it('clears the error from a not-found session while the new session loads', async () => {
        const handler = jest
          .fn()
          .mockResolvedValueOnce(notFoundResponse)
          .mockResolvedValue(pageOneResponse);
        createComponent({ handler });
        await waitForPromises();

        expect(wrapper.text()).toContain('Failed to load audit events.');

        await wrapper.setProps({
          activeItem: { ...mockActiveItem, id: OTHER_SESSION_ID },
        });

        // The error alert outranks the loading state in the list template, so
        // a stale flag would show the old session's error during the fetch.
        expect(wrapper.text()).not.toContain('Failed to load audit events.');

        await waitForPromises();

        expect(wrapper.text()).not.toContain('Failed to load audit events.');
        expect(wrapper.findByTestId('audit-events-timeline').exists()).toBe(true);
      });
    });
  });
  describe('when the aiGovernanceSessionsApi feature flag is enabled', () => {
    const GOVERNANCE_SESSION_ID = 'gid://gitlab/Ai::Governance::Session/502';
    const governanceItem = {
      ...mockActiveItem,
      id: GOVERNANCE_SESSION_ID,
      sessionId: 'abc-123',
      source: 'CLAUDE_CODE_GLAB',
      flowType: null,
      webPath: null,
      downloadPath: null,
    };

    const buildSessionsResponse = (parentKey, nodes) => ({
      data: {
        [parentKey]: {
          id: parentKey === 'project' ? 'gid://gitlab/Project/1' : 'gid://gitlab/Group/1',
          aiGovernanceSessions: {
            nodes,
            __typename: 'AiGovernanceSessionConnection',
          },
          __typename: parentKey === 'project' ? 'Project' : 'Group',
        },
      },
    });

    const sessionNode = {
      id: GOVERNANCE_SESSION_ID,
      auditEvents: {
        nodes: pageOneEvents.map(({ workflowId, ...event }) => event),
        pageInfo: {
          hasNextPage: false,
          hasPreviousPage: false,
          startCursor: 'event-1',
          endCursor: 'event-2',
          __typename: 'PageInfo',
        },
        __typename: 'AiAuditEventConnection',
      },
      __typename: 'AiGovernanceSession',
    };

    let legacyHandler;
    let linksHandler;

    const createSessionsComponent = ({
      query,
      handler,
      provide = {},
      activeItem = governanceItem,
      linksQuery = getProjectAiGovernanceSessionLinksQuery,
      linksResponse = jest.fn().mockResolvedValue(buildSessionLinksResponse('project')),
    }) => {
      legacyHandler = jest.fn().mockResolvedValue(pageOneResponse);
      linksHandler = linksResponse;
      const apolloProvider = createMockApollo([
        [getProjectSessionAuditEventsQuery, legacyHandler],
        [query, handler],
        [linksQuery, linksHandler],
      ]);

      wrapper = shallowMountExtended(SessionDetailsDrawer, {
        apolloProvider,
        provide: {
          projectFullPath: PROJECT_FULL_PATH,
          groupFullPath: null,
          glFeatures: { aiGovernanceSessionsApi: true },
          ...provide,
        },
        propsData: { activeItem },
        stubs: {
          MountingPortal: { template: '<div><slot /></div>' },
          DynamicPanel: { template: '<div><slot name="header" /><slot /></div>' },
          SessionDetailsBody,
          SessionAuditEventsList,
          CrudComponent,
          GlAttributeList,
          GlButton,
        },
      });
    };

    it('queries the project session by id instead of workflowId', async () => {
      const handler = jest.fn().mockResolvedValue(buildSessionsResponse('project', [sessionNode]));
      createSessionsComponent({ query: getProjectAiGovernanceSessionAuditEventsQuery, handler });
      await waitForPromises();

      expect(legacyHandler).not.toHaveBeenCalled();
      expect(handler).toHaveBeenCalledWith(
        expect.objectContaining({ projectFullPath: PROJECT_FULL_PATH, id: GOVERNANCE_SESSION_ID }),
      );
      expect(handler.mock.calls[0][0]).not.toHaveProperty('workflowId');
      expect(wrapper.findByTestId('audit-events-timeline').exists()).toBe(true);
    });

    it('queries the group session by id in group mode', async () => {
      const handler = jest.fn().mockResolvedValue(buildSessionsResponse('group', [sessionNode]));
      createSessionsComponent({
        query: getGroupAiGovernanceSessionAuditEventsQuery,
        handler,
        provide: { projectFullPath: null, groupFullPath: 'gitlab-org' },
      });
      await waitForPromises();

      expect(handler).toHaveBeenCalledWith(
        expect.objectContaining({ groupFullPath: 'gitlab-org', id: GOVERNANCE_SESSION_ID }),
      );
    });

    it('shows the error alert when the session is not found', async () => {
      const handler = jest.fn().mockResolvedValue(buildSessionsResponse('project', []));
      createSessionsComponent({ query: getProjectAiGovernanceSessionAuditEventsQuery, handler });
      await waitForPromises();

      expect(wrapper.text()).toContain('Failed to load audit events.');
    });

    it('skips the query when the active item has no id', async () => {
      const handler = jest.fn();
      createSessionsComponent({
        query: getProjectAiGovernanceSessionAuditEventsQuery,
        handler,
        activeItem: { ...governanceItem, id: null },
      });
      await waitForPromises();

      expect(handler).not.toHaveBeenCalled();
    });

    describe('session links', () => {
      const findLinkedItems = () => wrapper.findComponent(SessionLinkedItems);
      const auditEventsHandler = () =>
        jest.fn().mockResolvedValue(buildSessionsResponse('project', [sessionNode]));

      it('queries the project session links by id and shows them', async () => {
        createSessionsComponent({
          query: getProjectAiGovernanceSessionAuditEventsQuery,
          handler: auditEventsHandler(),
        });
        await waitForPromises();

        expect(linksHandler).toHaveBeenCalledWith({
          projectFullPath: PROJECT_FULL_PATH,
          id: GOVERNANCE_SESSION_ID,
        });
        expect(findSessionDetailsBody().props('links')).toEqual(mockGroupedSessionLinks);
        expect(findLinkedItems().exists()).toBe(true);
      });

      it('hides the previous session links while new links load', async () => {
        const sessionBId = 'gid://gitlab/Ai::Governance::Session/503';
        const sessionANode =
          buildSessionLinksResponse('project').data.project.aiGovernanceSessions.nodes[0];
        const sessionBResponse = buildSessionLinksResponse('project', [
          {
            ...sessionANode,
            id: sessionBId,
            mergeRequestLinks: buildLinkConnection(
              'AiGovernanceSessionMergeRequestLinkConnection',
              [
                {
                  ...sessionANode.mergeRequestLinks.nodes[0],
                  mergeRequest: {
                    ...sessionANode.mergeRequestLinks.nodes[0].mergeRequest,
                    title: 'Session B linked item',
                  },
                },
              ],
            ),
          },
        ]);
        let resolveSessionBLinks;
        const pendingSessionBLinks = new Promise((resolve) => {
          resolveSessionBLinks = resolve;
        });
        const linksResponse = jest
          .fn()
          .mockResolvedValueOnce(buildSessionLinksResponse('project'))
          .mockReturnValueOnce(pendingSessionBLinks);

        createSessionsComponent({
          query: getProjectAiGovernanceSessionAuditEventsQuery,
          handler: auditEventsHandler(),
          linksResponse,
        });
        await waitForPromises();

        expect(findLinkedItems().exists()).toBe(true);

        await wrapper.setProps({ activeItem: { ...governanceItem, id: sessionBId } });
        await waitForPromises();

        expect(findSessionDetailsBody().props('links')).toBeNull();
        expect(findLinkedItems().exists()).toBe(false);

        resolveSessionBLinks(sessionBResponse);
        await waitForPromises();

        expect(findSessionDetailsBody().props('links').startedFrom[0].title).toBe(
          'Session B linked item',
        );
        expect(findLinkedItems().exists()).toBe(true);
      });

      it('queries the group session links by id in group mode', async () => {
        createSessionsComponent({
          query: getGroupAiGovernanceSessionAuditEventsQuery,
          handler: jest.fn().mockResolvedValue(buildSessionsResponse('group', [sessionNode])),
          provide: { projectFullPath: null, groupFullPath: 'gitlab-org' },
          linksQuery: getGroupAiGovernanceSessionLinksQuery,
          linksResponse: jest.fn().mockResolvedValue(buildSessionLinksResponse('group')),
        });
        await waitForPromises();

        expect(linksHandler).toHaveBeenCalledWith({
          groupFullPath: 'gitlab-org',
          id: GOVERNANCE_SESSION_ID,
        });
        expect(findLinkedItems().exists()).toBe(true);
      });

      it('does not refetch the links when paging through the audit events', async () => {
        const handler = auditEventsHandler();
        createSessionsComponent({ query: getProjectAiGovernanceSessionAuditEventsQuery, handler });
        await waitForPromises();

        findSessionDetailsBody().vm.$emit('next', 'event-2');
        await waitForPromises();

        expect(handler).toHaveBeenCalledTimes(2);
        expect(handler).toHaveBeenLastCalledWith(expect.objectContaining({ after: 'event-2' }));
        expect(linksHandler).toHaveBeenCalledTimes(1);
      });

      it('does not show the linked items when the session has no links', async () => {
        createSessionsComponent({
          query: getProjectAiGovernanceSessionAuditEventsQuery,
          handler: auditEventsHandler(),
          linksResponse: jest.fn().mockResolvedValue(
            buildSessionLinksResponse('project', [
              {
                id: GOVERNANCE_SESSION_ID,
                mergeRequestLinks: buildLinkConnection(
                  'AiGovernanceSessionMergeRequestLinkConnection',
                ),
                noteLinks: buildLinkConnection('AiGovernanceSessionNoteLinkConnection'),
                workItemLinks: buildLinkConnection('AiGovernanceSessionWorkItemLinkConnection'),
                __typename: 'AiGovernanceSession',
              },
            ]),
          ),
        });
        await waitForPromises();

        expect(findLinkedItems().exists()).toBe(false);
      });

      it('hides the linked items without affecting the audit events when the query fails', async () => {
        createSessionsComponent({
          query: getProjectAiGovernanceSessionAuditEventsQuery,
          handler: auditEventsHandler(),
          linksResponse: jest.fn().mockRejectedValue(new Error('GraphQL error')),
        });
        await waitForPromises();

        expect(findLinkedItems().exists()).toBe(false);
        expect(findSessionDetailsBody().props('links')).toBeNull();
        expect(wrapper.findByTestId('audit-events-timeline').exists()).toBe(true);
        expect(wrapper.text()).not.toContain('Failed to load audit events.');
        expect(Sentry.captureException).toHaveBeenCalledWith(expect.any(Error));
      });

      it('skips the links query when the active item has no id', async () => {
        createSessionsComponent({
          query: getProjectAiGovernanceSessionAuditEventsQuery,
          handler: jest.fn(),
          activeItem: { ...governanceItem, id: null },
        });
        await waitForPromises();

        expect(linksHandler).not.toHaveBeenCalled();
      });

      it('skips the links query when the aiGovernanceSessionsApi flag is disabled', async () => {
        createSessionsComponent({
          query: getProjectAiGovernanceSessionAuditEventsQuery,
          handler: jest.fn(),
          provide: { glFeatures: { aiGovernanceSessionsApi: false } },
        });
        await waitForPromises();

        expect(legacyHandler).toHaveBeenCalled();
        expect(linksHandler).not.toHaveBeenCalled();
        expect(findLinkedItems().exists()).toBe(false);
      });
    });
  });
});
