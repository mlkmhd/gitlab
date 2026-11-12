import Vue, { nextTick } from 'vue';
import VueApollo from 'vue-apollo';
import { GlAvatar, GlAvatarLink, GlLink } from '@gitlab/ui';
import { shallowMountExtended } from 'helpers/vue_test_utils_helper';
import createMockApollo from 'helpers/mock_apollo_helper';
import waitForPromises from 'helpers/wait_for_promises';
import { createMockDirective, getBinding } from 'helpers/vue_mock_directive';
import * as Sentry from '~/sentry/sentry_browser_wrapper';
import {
  AGENT_PLATFORM_STATUS_FAILED,
  AGENT_PLATFORM_STATUS_STOPPED,
} from 'ee/ai/duo_agents_platform/constants';
import AgentSessionRow from 'ee/ai/shared/widgets/agent_session_row.vue';
import AgentSessionActions from 'ee/ai/duo_agents_platform/pages/show/components/agent_session_actions.vue';
import { eventHub, REFETCH_SESSIONS, SHOW_SESSION } from 'ee/ai/events/panel';
import { restartWorkflow } from 'ee/rest_api';
import duoChatAvailableQuery from 'ee/ai/graphql/duo_chat_available.query.graphql';
import TimeAgoTooltip from '~/vue_shared/components/time_ago_tooltip.vue';
import { buildSession, mockUser1 } from 'ee_jest/ai/mocks';

Vue.use(VueApollo);

jest.mock('~/sentry/sentry_browser_wrapper');
jest.mock('ee/rest_api');

describe('AgentSessionRow', () => {
  let wrapper;
  const showToast = jest.fn();
  const mockRestartedAs = {
    id: 'gid://gitlab/Ai::DuoWorkflows::Workflow/2',
    webPath: '/group/project/-/automate/agent-sessions/2',
  };

  const createComponent = (
    session,
    props = {},
    { duoChatAvailable = false, dapSessionRestarts = true } = {},
  ) => {
    wrapper = shallowMountExtended(AgentSessionRow, {
      propsData: { session, ...props },
      provide: { glFeatures: { dapSessionRestarts } },
      directives: { GlTooltip: createMockDirective('gl-tooltip') },
      mocks: { $toast: { show: showToast } },
      apolloProvider: createMockApollo([
        [
          duoChatAvailableQuery,
          jest.fn().mockResolvedValue({
            data: { currentUser: { id: 'gid://gitlab/User/1', duoChatAvailable } },
          }),
        ],
      ]),
    });

    return waitForPromises();
  };

  const findTitle = () => wrapper.findByTestId('session-title');
  const findTitleLink = () => wrapper.findComponent(GlLink);
  const findViewDetailsButton = () => wrapper.findByTestId('session-view-details-button');
  const findTitleButtonComponent = () => wrapper.findComponentByTestId('session-title');
  const findViewDetailsButtonComponent = () =>
    wrapper.findComponentByTestId('session-view-details-button');
  const findTimeAgoTooltip = () => wrapper.findComponent(TimeAgoTooltip);
  const findAvatarLink = () => wrapper.findComponent(GlAvatarLink);
  const findAvatar = () => wrapper.findComponent(GlAvatar);
  const findSessionActions = () => wrapper.findComponent(AgentSessionActions);
  const findViewRetryLink = () => wrapper.findComponentByTestId('session-view-retry-link');

  describe('opening a session', () => {
    const clickEvent = (modifiers = {}) => ({ preventDefault: jest.fn(), ...modifiers });
    const clickTargets = {
      title: () => findTitleLink(),
      'View details': () => findViewDetailsButtonComponent(),
    };

    beforeEach(() => {
      jest.spyOn(eventHub, '$emit');
    });

    describe('when the Duo panel is available', () => {
      beforeEach(() =>
        createComponent(buildSession(), { showViewDetails: true }, { duoChatAvailable: true }),
      );

      it.each(Object.keys(clickTargets))('opens the session in the panel from the %s', (target) => {
        const event = clickEvent();
        clickTargets[target]().vm.$emit('click', event);

        expect(event.preventDefault).toHaveBeenCalled();
        expect(eventHub.$emit).toHaveBeenCalledWith(SHOW_SESSION, { id: 1 });
      });

      describe.each(['metaKey', 'ctrlKey', 'shiftKey'])('when the click uses %s', (modifier) => {
        let event;

        beforeEach(() => {
          event = clickEvent({ [modifier]: true });
          findTitleLink().vm.$emit('click', event);
        });

        it('follows the link', () => {
          expect(event.preventDefault).not.toHaveBeenCalled();
          expect(eventHub.$emit).not.toHaveBeenCalled();
        });
      });
    });

    describe('when the session has no web path, but the Duo panel is available', () => {
      beforeEach(() =>
        createComponent(
          buildSession({ project: null, webPath: null }),
          { showViewDetails: true },
          { duoChatAvailable: true },
        ),
      );

      it('renders the title as a link-style button', () => {
        expect(findTitleLink().exists()).toBe(false);
        expect(findTitleButtonComponent().props('variant')).toBe('link');
      });

      it.each`
        target            | find
        ${'title'}        | ${() => findTitleButtonComponent()}
        ${'View details'} | ${() => findViewDetailsButtonComponent()}
      `('opens the session in the panel from the $target', ({ find }) => {
        find().vm.$emit('click', clickEvent());

        expect(eventHub.$emit).toHaveBeenCalledWith(SHOW_SESSION, { id: 1 });
      });
    });

    describe('when the Duo panel is not available', () => {
      beforeEach(() => createComponent(buildSession(), { showViewDetails: true }));

      it.each(Object.keys(clickTargets))('follows the link from the %s', (target) => {
        const event = clickEvent();
        clickTargets[target]().vm.$emit('click', event);

        expect(event.preventDefault).not.toHaveBeenCalled();
        expect(eventHub.$emit).not.toHaveBeenCalled();
      });
    });
  });

  describe('title', () => {
    describe('when the session has a web path', () => {
      beforeEach(() => {
        createComponent(buildSession({ title: 'Custom generated title' }));
      });

      it('links to the session page', () => {
        expect(findTitleLink().text()).toBe('Custom generated title');
        expect(findTitleLink().attributes('href')).toBe(
          '/group/project/-/automate/agent-sessions/1',
        );
      });

      it('shows the title and id in a tooltip', () => {
        expect(getBinding(findTitle().element, 'gl-tooltip')).toBeDefined();
        expect(findTitle().attributes('title')).toBe('Custom generated title 1');
      });
    });

    describe('when the session belongs to a group', () => {
      beforeEach(() => {
        createComponent(
          buildSession({ project: null, webPath: '/groups/group/-/automate/agent-sessions/1' }),
        );
      });

      it('links to the group session page', () => {
        expect(findTitleLink().attributes('href')).toBe(
          '/groups/group/-/automate/agent-sessions/1',
        );
      });
    });

    describe('when the session has no web path', () => {
      beforeEach(() => {
        createComponent(buildSession({ title: 'Custom generated title', webPath: null }));
      });

      it('renders the title as plain text', () => {
        expect(findTitleLink().exists()).toBe(false);
        expect(findTitle().text()).toBe('Custom generated title');
      });

      it('keeps the tooltip reachable by keyboard', () => {
        expect(getBinding(findTitle().element, 'gl-tooltip')).toBeDefined();
        expect(findTitle().attributes('tabindex')).toBe('0');
        expect(findTitle().attributes('title')).toBe('Custom generated title 1');
      });
    });

    describe('when the session has a title', () => {
      beforeEach(() => {
        createComponent(buildSession({ title: 'Custom generated title' }));
      });

      it('renders the title', () => {
        expect(findTitle().text()).toBe('Custom generated title');
      });
    });

    describe('when the session has no title', () => {
      beforeEach(() => {
        createComponent(buildSession({ title: null }));
      });

      it('falls back to the humanized workflow definition', () => {
        expect(findTitle().text()).toBe('Planner');
      });
    });
  });

  describe('updated at', () => {
    describe('when updatedAt is present', () => {
      beforeEach(() => {
        createComponent(buildSession());
      });

      it('renders TimeAgoTooltip', () => {
        expect(findTimeAgoTooltip().props('time')).toBe('2026-01-15T10:00:00Z');
      });
    });

    describe('when updatedAt is absent', () => {
      beforeEach(() => {
        createComponent(buildSession({ updatedAt: null }));
      });

      it('does not render TimeAgoTooltip', () => {
        expect(findTimeAgoTooltip().exists()).toBe(false);
      });
    });
  });

  describe('"View details" button', () => {
    describe('when showViewDetails is true', () => {
      beforeEach(() => {
        createComponent(buildSession(), { showViewDetails: true });
      });

      it('renders as a confirm/tertiary link to the session URL', () => {
        expect(findViewDetailsButton().exists()).toBe(true);
        expect(findViewDetailsButton().text()).toBe('View details');
        expect(findViewDetailsButton().attributes('variant')).toBe('confirm');
        expect(findViewDetailsButton().attributes('category')).toBe('tertiary');
        expect(findViewDetailsButton().attributes('href')).toBe(
          '/group/project/-/automate/agent-sessions/1',
        );
      });
    });

    describe('when there is no web path and the Duo panel is not available', () => {
      beforeEach(() => {
        createComponent(buildSession({ webPath: null }), { showViewDetails: true });
      });

      it('does not render', () => {
        expect(findViewDetailsButton().exists()).toBe(false);
      });
    });

    describe('when showViewDetails is false', () => {
      beforeEach(() => {
        createComponent(buildSession());
      });

      it('does not render', () => {
        expect(findViewDetailsButton().exists()).toBe(false);
      });
    });
  });

  describe('user avatar', () => {
    describe('when the session has a user', () => {
      beforeEach(() => {
        createComponent(buildSession({ user: mockUser1 }));
      });

      it('renders GlAvatarLink with the correct attributes', () => {
        expect(findAvatarLink().attributes('href')).toBe(mockUser1.webPath);
        expect(findAvatarLink().attributes('title')).toBe(mockUser1.name);
        expect(findAvatarLink().attributes('data-username')).toBe(mockUser1.username);
        expect(findAvatarLink().attributes('data-user-id')).toBe('1');
      });

      it('renders GlAvatar with the correct props', () => {
        expect(findAvatar().props('src')).toBe(mockUser1.avatarUrl);
        expect(findAvatar().props('entityName')).toBe(mockUser1.name);
        expect(findAvatar().props('size')).toBe(16);
      });
    });

    describe('when the session has no user', () => {
      beforeEach(() => {
        createComponent(buildSession());
      });

      it('does not render', () => {
        expect(findAvatarLink().exists()).toBe(false);
      });
    });
  });

  describe('retry action', () => {
    const restartableSession = (status) =>
      buildSession({ status, userPermissions: { restartDuoWorkflow: true } });

    describe.each([AGENT_PLATFORM_STATUS_FAILED, AGENT_PLATFORM_STATUS_STOPPED])(
      'when a %s session can be restarted',
      (status) => {
        beforeEach(() => createComponent(restartableSession(status)));

        it('renders the minimal session actions', () => {
          expect(findSessionActions().props()).toMatchObject({
            status,
            canRestartWorkflow: true,
            isRetrying: false,
            displayMinimal: true,
            iconButtonCategory: 'tertiary',
          });
        });

        it('names the retry button after the session', () => {
          expect(findSessionActions().props('retryAriaLabel')).toBe(
            `Retry session ${findTitle().text()}`,
          );
        });
      },
    );

    describe('when the user cannot restart the session', () => {
      beforeEach(() =>
        createComponent(
          buildSession({
            status: AGENT_PLATFORM_STATUS_FAILED,
            userPermissions: { restartDuoWorkflow: false },
          }),
        ),
      );

      it('does not render the session actions', () => {
        expect(findSessionActions().exists()).toBe(false);
      });
    });

    describe('when dapSessionRestarts is disabled', () => {
      beforeEach(() =>
        createComponent(
          restartableSession(AGENT_PLATFORM_STATUS_FAILED),
          {},
          { dapSessionRestarts: false },
        ),
      );

      it('does not render the session actions', () => {
        expect(findSessionActions().exists()).toBe(false);
      });
    });

    describe('when the session is retried', () => {
      beforeEach(async () => {
        jest.spyOn(eventHub, '$emit');
        restartWorkflow.mockResolvedValue({ data: { id: 42 } });

        await createComponent(restartableSession(AGENT_PLATFORM_STATUS_FAILED));
        findSessionActions().vm.$emit('retry-session');
        await waitForPromises();
      });

      it('restarts the session', () => {
        expect(restartWorkflow).toHaveBeenCalledWith(1);
      });

      it('refetches the sessions', () => {
        expect(eventHub.$emit).toHaveBeenCalledWith(REFETCH_SESSIONS);
      });

      it('does not open a session', () => {
        expect(eventHub.$emit).not.toHaveBeenCalledWith(SHOW_SESSION, expect.anything());
      });

      it('does not show a message, since the new session shows in the list', () => {
        expect(showToast).not.toHaveBeenCalled();
      });

      it('announces the restart to screen readers', () => {
        expect(wrapper.element.ariaNotify).toHaveBeenCalledWith(
          'Session has been restarted successfully.',
        );
      });

      it('clears the loading state', () => {
        expect(findSessionActions().props('isRetrying')).toBe(false);
      });
    });

    describe('while the retry request is in flight', () => {
      beforeEach(async () => {
        restartWorkflow.mockReturnValue(new Promise(() => {}));

        await createComponent(restartableSession(AGENT_PLATFORM_STATUS_FAILED));
        findSessionActions().vm.$emit('retry-session');
        await nextTick();
      });

      it('shows the loading state', () => {
        expect(findSessionActions().props('isRetrying')).toBe(true);
      });
    });

    describe('when the retry request fails', () => {
      const error = {
        response: { status: 409, data: { message: 'Workflow is already being restarted' } },
      };

      beforeEach(async () => {
        jest.spyOn(eventHub, '$emit');
        restartWorkflow.mockRejectedValue(error);

        await createComponent(restartableSession(AGENT_PLATFORM_STATUS_FAILED));
        findSessionActions().vm.$emit('retry-session');
        await waitForPromises();
      });

      it('shows a toast', () => {
        expect(showToast).toHaveBeenCalledWith('Failed to retry session. Please try again.');
      });

      it('does not announce a restart', () => {
        expect(wrapper.element.ariaNotify).not.toHaveBeenCalled();
      });

      it('reports the error to Sentry', () => {
        expect(Sentry.captureException).toHaveBeenCalledWith(error);
      });

      it('does not refetch the sessions', () => {
        expect(eventHub.$emit).not.toHaveBeenCalledWith(REFETCH_SESSIONS);
      });

      it('clears the loading state so the button can be used again', () => {
        expect(findSessionActions().props('isRetrying')).toBe(false);
      });
    });
  });

  describe('"View retry" link', () => {
    const retriedSession = buildSession({
      status: AGENT_PLATFORM_STATUS_FAILED,
      userPermissions: { restartDuoWorkflow: true },
      restartedAs: mockRestartedAs,
    });

    describe('when the session has been retried', () => {
      beforeEach(() => createComponent(retriedSession));

      it('links to the newest retry', () => {
        expect(findViewRetryLink().text()).toBe('View retry');
        expect(findViewRetryLink().attributes('href')).toBe(mockRestartedAs.webPath);
      });

      it('names the link after the session', () => {
        expect(findViewRetryLink().attributes('aria-label')).toBe(
          `View retry of session ${findTitle().text()}`,
        );
      });

      it('does not render the retry action', () => {
        expect(findSessionActions().exists()).toBe(false);
      });
    });

    describe('when the Duo panel is available', () => {
      beforeEach(async () => {
        jest.spyOn(eventHub, '$emit');
        await createComponent(retriedSession, {}, { duoChatAvailable: true });
      });

      it('opens the newest retry in the panel', () => {
        const event = { preventDefault: jest.fn() };
        findViewRetryLink().vm.$emit('click', event);

        expect(event.preventDefault).toHaveBeenCalled();
        expect(eventHub.$emit).toHaveBeenCalledWith(SHOW_SESSION, { id: 2 });
      });

      describe('when the click uses a modifier key', () => {
        let event;

        beforeEach(() => {
          event = { preventDefault: jest.fn(), ctrlKey: true };
          findViewRetryLink().vm.$emit('click', event);
        });

        it('follows the link', () => {
          expect(event.preventDefault).not.toHaveBeenCalled();
          expect(eventHub.$emit).not.toHaveBeenCalled();
        });
      });
    });

    describe('when the session has not been retried', () => {
      beforeEach(() =>
        createComponent(
          buildSession({
            status: AGENT_PLATFORM_STATUS_FAILED,
            userPermissions: { restartDuoWorkflow: true },
          }),
        ),
      );

      it('does not render the link', () => {
        expect(findViewRetryLink().exists()).toBe(false);
      });
    });

    describe('when dapSessionRestarts is disabled', () => {
      beforeEach(() => createComponent(retriedSession, {}, { dapSessionRestarts: false }));

      it('does not render the link', () => {
        expect(findViewRetryLink().exists()).toBe(false);
      });
    });
  });
});
