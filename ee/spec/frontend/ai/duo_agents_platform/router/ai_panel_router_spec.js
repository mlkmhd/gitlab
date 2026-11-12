import { eventHub, SHOW_SESSION, SHOW_NEW_CHAT } from 'ee/ai/events/panel';
import waitForPromises from 'helpers/wait_for_promises';
import { duoChatGlobalState, CHAT_MODES } from 'ee/ai/state';
import { createRouter } from 'ee/ai/duo_agents_platform/router/ai_panel_router';
import {
  AGENTS_PLATFORM_INDEX_ROUTE,
  AGENTS_PLATFORM_SHOW_ROUTE,
  AGENTIC_CHAT_NEW_ROUTE,
  AGENTIC_CHAT_SHOW_ROUTE,
  CLASSIC_CHAT_NEW_ROUTE,
  CLOSED_ROUTE,
  MAX_HISTORY_STACK_SIZE,
} from 'ee/ai/duo_agents_platform/router/constants';
import { DUO_CURRENT_WORKFLOW_STORAGE_KEY } from 'ee/ai/constants';
import AgentSessionInbox from 'ee/ai/duo_agents_platform/panel/agent_session_inbox.vue';

jest.mock('ee/ai/events/panel');
jest.mock('ee/ai/duo_agents_platform/utils/navigation_state', () => ({
  getStorageKey: jest.fn(),
  restoreLastRoute: jest.fn(),
  saveRouteState: jest.fn(),
  setupNavigationGuards: jest.fn(),
  trackTabRoutes: jest.fn(),
}));
jest.mock('~/lib/utils/local_storage', () => ({
  ...jest.requireActual('~/lib/utils/local_storage'),
  removeSessionStorageValue: jest.fn(),
}));

describe('ai panel router', () => {
  let eventHandlers;
  let router;

  beforeEach(() => {
    eventHandlers = {};
    eventHub.$on.mockImplementation((event, handler) => {
      eventHandlers[event] = handler;
    });
    const chatConfiguration = {
      defaultProps: {
        isAgenticAvailable: true,
        isClassicAvailable: true,
      },
    };
    router = createRouter('/project', 'panel', chatConfiguration);
  });

  it('listens for SHOW_SESSION events', () => {
    expect(eventHub.$on).toHaveBeenCalledWith(SHOW_SESSION, expect.any(Function));
  });

  it('listens for SHOW_NEW_CHAT events', () => {
    expect(eventHub.$on).toHaveBeenCalledWith(SHOW_NEW_CHAT, expect.any(Function));
  });

  it('pushes the show session route with the provided id', async () => {
    const id = '5';
    eventHandlers[SHOW_SESSION]({ id });

    await waitForPromises();

    expect(router.currentRoute.name).toBe(AGENTS_PLATFORM_SHOW_ROUTE);
    expect(router.currentRoute.params).toEqual({ id });
  });

  describe('SHOW_NEW_CHAT handler', () => {
    it('navigates to agentic new chat route when in agentic mode', async () => {
      duoChatGlobalState.chatMode = CHAT_MODES.AGENTIC;
      eventHandlers[SHOW_NEW_CHAT]();

      await waitForPromises();

      expect(router.currentRoute.name).toBe(AGENTIC_CHAT_NEW_ROUTE);
    });

    it('navigates to classic new chat route when in classic mode', async () => {
      duoChatGlobalState.chatMode = CHAT_MODES.CLASSIC;
      eventHandlers[SHOW_NEW_CHAT]();

      await waitForPromises();

      expect(router.currentRoute.name).toBe(CLASSIC_CHAT_NEW_ROUTE);
    });
  });

  it('includes a closed route', () => {
    const closedRoute = router.options.routes.find((r) => r.name === CLOSED_ROUTE);
    expect(closedRoute).toBeDefined();
    expect(closedRoute.path).toBe('/closed');
  });

  describe('initial-route resolution by autoExpand', () => {
    const { restoreLastRoute } = jest.requireMock(
      'ee/ai/duo_agents_platform/utils/navigation_state',
    );

    beforeEach(() => {
      restoreLastRoute.mockClear();
    });

    it('passes CLOSED_ROUTE as defaultRoute when autoExpand is false', () => {
      createRouter('/', 'user', {
        defaultProps: { isAgenticAvailable: true },
        autoExpand: false,
      });

      expect(restoreLastRoute).toHaveBeenCalledWith(
        expect.anything(),
        expect.objectContaining({ defaultRoute: CLOSED_ROUTE }),
      );
    });

    it('leaves defaultRoute undefined when autoExpand is true', () => {
      createRouter('/', 'user', {
        defaultProps: { isAgenticAvailable: true },
        autoExpand: true,
      });

      expect(restoreLastRoute).toHaveBeenCalledWith(
        expect.anything(),
        expect.objectContaining({ defaultRoute: undefined }),
      );
    });
  });

  describe('sessions index component', () => {
    const findSessionsIndexComponent = (routerInstance) =>
      routerInstance.options.routes
        .flatMap((route) => route.children ?? [])
        .find((route) => route.name === AGENTS_PLATFORM_INDEX_ROUTE).component;

    it('uses the inbox on the side panel', () => {
      const sidePanelRouter = createRouter('/', 'side_panel', {
        defaultProps: { isAgenticAvailable: true },
      });

      expect(findSessionsIndexComponent(sidePanelRouter)).toBe(AgentSessionInbox);
    });
  });

  describe('navigation history', () => {
    const pushSession = (id) => router.push({ name: AGENTS_PLATFORM_SHOW_ROUTE, params: { id } });
    const historyIds = () => router.navigationHistory.stack.map(({ params }) => params.id);
    const goBack = async () => {
      router.back();
      await waitForPromises();
    };

    describe('when there is one route', () => {
      beforeEach(async () => {
        await pushSession('1');
      });

      it('cannot go back', () => {
        expect(router.canGoBack()).toBe(false);
      });
    });

    describe('when there is an earlier route', () => {
      beforeEach(async () => {
        await pushSession('1');
        await pushSession('2');
      });

      it('can go back', () => {
        expect(router.canGoBack()).toBe(true);
      });

      describe('when going back', () => {
        beforeEach(goBack);

        it('returns to the earlier route', () => {
          expect(router.currentRoute.params).toEqual({ id: '1' });
          expect(router.canGoBack()).toBe(false);
        });

        describe('when navigating again', () => {
          beforeEach(async () => {
            await pushSession('3');
          });

          it('drops the forward history', () => {
            expect(historyIds()).toEqual(['1', '3']);
          });
        });
      });
    });

    describe('when going back with no earlier route', () => {
      beforeEach(async () => {
        await pushSession('1');
        await goBack();
        await pushSession('2');
      });

      it('records the next navigation as a new entry', () => {
        expect(historyIds()).toEqual(['1', '2']);
        expect(router.navigationHistory.index).toBe(1);
      });
    });

    describe('when a navigation fails', () => {
      beforeEach(async () => {
        await pushSession('1');
        await pushSession('1').catch(() => {});
      });

      it('does not add an entry', () => {
        expect(historyIds()).toEqual(['1']);
        expect(router.canGoBack()).toBe(false);
      });
    });

    describe('when there are more than MAX_HISTORY_STACK_SIZE navigations', () => {
      beforeEach(async () => {
        const ids = Array.from({ length: MAX_HISTORY_STACK_SIZE + 1 }, (_, i) => String(i + 1));
        await ids.reduce((previous, id) => previous.then(() => pushSession(id)), Promise.resolve());
      });

      it('drops the oldest entries', () => {
        expect(historyIds()).toHaveLength(MAX_HISTORY_STACK_SIZE);
        expect(historyIds()[0]).toBe('2');
        expect(router.navigationHistory.index).toBe(MAX_HISTORY_STACK_SIZE - 1);
      });
    });
  });

  describe('event-listener teardown', () => {
    it('exposes a `cleanupEventListeners` function on the router', () => {
      expect(typeof router.cleanupEventListeners).toBe('function');
    });

    it('removes SHOW_SESSION and SHOW_NEW_CHAT listeners when invoked', () => {
      router.cleanupEventListeners();

      expect(eventHub.$off).toHaveBeenCalledWith(SHOW_SESSION, expect.any(Function));
      expect(eventHub.$off).toHaveBeenCalledWith(SHOW_NEW_CHAT, expect.any(Function));
    });
  });

  describe('beforeEach guard clears stale workflow on new-chat navigation', () => {
    const { removeSessionStorageValue } = jest.requireMock('~/lib/utils/local_storage');

    beforeEach(() => {
      removeSessionStorageValue.mockClear();
    });

    it('clears workflow storage when navigating to agentic new chat route', async () => {
      router.push({ name: AGENTIC_CHAT_NEW_ROUTE });
      await waitForPromises();

      expect(removeSessionStorageValue).toHaveBeenCalledWith(DUO_CURRENT_WORKFLOW_STORAGE_KEY);
    });

    it('clears workflow storage when navigating to classic new chat route', async () => {
      router.push({ name: CLASSIC_CHAT_NEW_ROUTE });
      await waitForPromises();

      expect(removeSessionStorageValue).toHaveBeenCalledWith(DUO_CURRENT_WORKFLOW_STORAGE_KEY);
    });

    it('does NOT clear workflow storage when navigating to agentic show route', async () => {
      router.push({ name: AGENTIC_CHAT_SHOW_ROUTE });
      await waitForPromises();

      expect(removeSessionStorageValue).not.toHaveBeenCalled();
    });
  });
});
