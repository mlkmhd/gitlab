import { print } from 'graphql';
import Vue, { nextTick } from 'vue';
import VueApollo from 'vue-apollo';
import { createMockSubscription } from 'mock-apollo-client';
import { shallowMountExtended } from 'helpers/vue_test_utils_helper';
import createMockApollo from 'helpers/mock_apollo_helper';
import { config } from '~/graphql_shared/issuable_client';
import waitForPromises from 'helpers/wait_for_promises';
import ImplementationWidget from 'ee/work_items/components/implementation_widget/implementation_widget.vue';
import WorkItemReadiness from 'ee/work_items/components/implementation_widget/work_item_readiness.vue';
import WorkItemWorkplan from 'ee/work_items/components/implementation_widget/work_item_workplan.vue';
import workItemAgentPlanQuery from 'ee/work_items/graphql/work_item_agent_plan.query.graphql';
import workItemAgentPlanReadinessFeedbackQuery from 'ee/work_items/graphql/work_item_agent_plan_readiness_feedback.query.graphql';
import workItemAgentPlanUpdatedSubscription from 'ee/work_items/graphql/work_item_agent_plan.subscription.graphql';
import getDuoAgentSessionsOnWorkItemQuery from 'ee/ai/shared/widgets/graphql/get_duo_agent_sessions_on_work_item.query.graphql';
import { buildSession, buildWorkItemSessionsQueryResponse } from 'ee_jest/ai/mocks';
import { buildAgentPlanWidgetMock } from 'ee_jest/work_items/mock_data';
import { createAlert } from '~/alert';
import * as Sentry from '~/sentry/sentry_browser_wrapper';
import { WORKPLAN_PANEL } from '~/work_items/constants';
import { ACTIVE_RUN_POLL_INTERVAL_MS } from 'ee/work_items/components/implementation_widget/constants';

jest.mock('~/alert');
jest.mock('~/sentry/sentry_browser_wrapper');

Vue.use(VueApollo);

describe('ImplementationWidget', () => {
  let wrapper;
  let apolloProvider;

  const mockWorkItemId = 'gid://gitlab/WorkItem/1';
  const workItem = { id: mockWorkItemId };

  const workplanResponse = ({
    content = 'a plan',
    contentHtml = '<p>a plan</p>',
    aiPlanningEnabled = true,
    readinessScore = null,
    generationStatus = null,
  } = {}) => {
    const workplan = buildAgentPlanWidgetMock({
      content,
      contentHtml,
      aiPlanningEnabled,
      readinessScore,
      generationStatus,
    });

    return {
      data: {
        workItem: {
          __typename: 'WorkItem',
          id: mockWorkItemId,
          iid: '1',
          features: { __typename: 'WorkItemFeatures', agentPlan: workplan },
        },
      },
    };
  };

  const feedbackResponse = (readinessScoreFeedbackHtml = '<p>Feedback</p>') => {
    const agentPlan = {
      __typename: 'WorkItemWidgetAgentPlan',
      type: 'AGENT_PLAN',
      readinessScoreFeedbackHtml,
    };

    return {
      data: {
        workItem: {
          __typename: 'WorkItem',
          id: mockWorkItemId,
          features: { __typename: 'WorkItemFeatures', agentPlan },
        },
      },
    };
  };

  const developerSession = buildSession({
    id: 'gid://gitlab/Ai::DuoWorkflows::Workflow/11',
    workflowDefinition: 'developer/v1',
    status: 'RUNNING',
  });
  const workplanSession = buildSession({
    id: 'gid://gitlab/Ai::DuoWorkflows::Workflow/12',
    workflowDefinition: 'workplan/v1',
  });

  const createComponent = ({
    props = {},
    glFeatures = {},
    queryHandler = jest.fn().mockResolvedValue(workplanResponse({ readinessScore: 85 })),
    feedbackHandler = jest.fn().mockResolvedValue(feedbackResponse()),
    subscriptionHandler = jest.fn().mockResolvedValue({ data: null }),
    sessionsHandler = jest.fn().mockResolvedValue(buildWorkItemSessionsQueryResponse()),
  } = {}) => {
    apolloProvider = createMockApollo(
      [
        [workItemAgentPlanQuery, queryHandler],
        [workItemAgentPlanReadinessFeedbackQuery, feedbackHandler],
        [workItemAgentPlanUpdatedSubscription, subscriptionHandler],
        [getDuoAgentSessionsOnWorkItemQuery, sessionsHandler],
      ],
      {},
      config.cacheConfig,
    );
    wrapper = shallowMountExtended(ImplementationWidget, {
      apolloProvider,
      propsData: { workItem, ...props },
      provide: { glFeatures },
    });
  };

  const findReadiness = () => wrapper.findComponent(WorkItemReadiness);
  const findWorkplan = () => wrapper.findComponent(WorkItemWorkplan);

  it('always renders the work plan child', () => {
    createComponent();
    expect(findWorkplan().exists()).toBe(true);
  });

  it('forwards props to the work plan child', () => {
    createComponent({
      props: { canUpdate: true, workItemWebUrl: '/url', isInDrawer: true, isPanelOpen: true },
    });
    expect(findWorkplan().props()).toMatchObject({
      workItem,
      canUpdate: true,
      workItemWebUrl: '/url',
      isInDrawer: true,
      isPanelOpen: true,
    });
  });

  it('re-emits request-panel from the work plan child', () => {
    createComponent();
    findWorkplan().vm.$emit('request-panel', WORKPLAN_PANEL);
    expect(wrapper.emitted('request-panel')).toEqual([[WORKPLAN_PANEL]]);
  });

  describe('workplan query', () => {
    it('marks the work plan as loading until the query settles', async () => {
      createComponent();

      expect(findWorkplan().props('isLoading')).toBe(true);

      await waitForPromises();

      expect(findWorkplan().props('isLoading')).toBe(false);
    });

    it('passes the queried plan down to the work plan child', async () => {
      createComponent();
      await waitForPromises();

      expect(findWorkplan().props('workplan')).toMatchObject({ hasContent: true });
    });

    it('does not load the plan content', async () => {
      createComponent();
      await waitForPromises();

      expect(findWorkplan().props('workplan')).not.toHaveProperty('content');
      expect(findWorkplan().props('workplan')).not.toHaveProperty('contentHtml');
    });

    it.each([
      ['polled query', workItemAgentPlanQuery],
      ['subscription', workItemAgentPlanUpdatedSubscription],
    ])('does not select the plan content in the %s', (_, document) => {
      expect(print(document)).not.toMatch(/\bcontent(Html)?\b/);
    });

    describe('when the work item has no id yet', () => {
      const queryHandler = jest.fn().mockResolvedValue(workplanResponse());

      beforeEach(async () => {
        createComponent({ props: { workItem: {} }, queryHandler });
        await waitForPromises();
      });

      it('does not query', () => {
        expect(queryHandler).not.toHaveBeenCalled();
      });
    });

    describe('when the query errors', () => {
      beforeEach(async () => {
        createComponent({ queryHandler: jest.fn().mockRejectedValue(new Error('boom')) });
        await waitForPromises();
      });

      it('leaves the plan empty', () => {
        expect(findWorkplan().props('workplan')).toBe(null);
      });

      it('tells the user the plan could not be fetched and reports the error', () => {
        expect(createAlert).toHaveBeenCalledWith({
          message: 'Something went wrong when fetching the workplan. Please refresh this page.',
          captureError: true,
          error: expect.any(Error),
        });
      });
    });
  });

  describe('readiness score', () => {
    const openDrawer = async () => {
      await findReadiness().vm.$emit('toggle');
      await waitForPromises();
    };

    describe('when the user toggles readiness details', () => {
      let queryHandler;
      let feedbackHandler;
      let subscriptionHandler;

      beforeEach(async () => {
        queryHandler = jest.fn().mockResolvedValue(workplanResponse({ readinessScore: 85 }));
        feedbackHandler = jest.fn().mockResolvedValue(feedbackResponse());
        subscriptionHandler = jest.fn(() => createMockSubscription());
        createComponent({
          glFeatures: { workplanScore: true },
          queryHandler,
          feedbackHandler,
          subscriptionHandler,
        });
        await waitForPromises();
      });

      it('does not request feedback while the drawer is closed', () => {
        expect(feedbackHandler).not.toHaveBeenCalled();
      });

      it('requests feedback once the drawer opens', async () => {
        await openDrawer();

        expect(feedbackHandler).toHaveBeenCalledTimes(1);
        expect(feedbackHandler).toHaveBeenCalledWith({
          id: mockWorkItemId,
          useWorkItemFeatures: true,
        });
        expect(findReadiness().props('feedbackHtml')).toBe('<p>Feedback</p>');
      });

      it('leaves the workplan query and its subscription untouched', async () => {
        await openDrawer();
        await findReadiness().vm.$emit('close');
        await waitForPromises();

        expect(queryHandler).toHaveBeenCalledTimes(1);
        expect(subscriptionHandler).toHaveBeenCalledTimes(1);
      });
    });

    describe('when fetching feedback fails', () => {
      let feedbackHandler;

      beforeEach(async () => {
        feedbackHandler = jest.fn().mockRejectedValue(new Error('feedback failed'));
        createComponent({
          glFeatures: { workplanScore: true },
          feedbackHandler,
        });
        await waitForPromises();
        await openDrawer();
      });

      it('keeps the workplan mounted', () => {
        expect(findWorkplan().exists()).toBe(true);
      });

      it('reports the error in the drawer instead of a page-level alert', () => {
        expect(findReadiness().props()).toMatchObject({ hasError: true, isLoading: false });
        expect(createAlert).not.toHaveBeenCalled();
        expect(Sentry.captureException).toHaveBeenCalledWith(expect.any(Error));
      });

      it('clears the error and loads feedback on retry', async () => {
        feedbackHandler.mockResolvedValue(feedbackResponse());
        await findReadiness().vm.$emit('retry');
        await waitForPromises();

        expect(feedbackHandler).toHaveBeenCalledTimes(2);
        expect(findReadiness().props()).toMatchObject({
          hasError: false,
          isLoading: false,
          feedbackHtml: '<p>Feedback</p>',
        });
      });

      it('shows the error again after a failed retry', async () => {
        await findReadiness().vm.$emit('retry');
        await waitForPromises();

        expect(feedbackHandler).toHaveBeenCalledTimes(2);
        expect(findReadiness().props()).toMatchObject({ hasError: true, isLoading: false });
      });

      it('loads feedback after closing and reopening the drawer', async () => {
        await findReadiness().vm.$emit('close');
        await waitForPromises();
        feedbackHandler.mockResolvedValue(feedbackResponse());
        await openDrawer();

        expect(findReadiness().props()).toMatchObject({
          isDrawerOpen: true,
          hasError: false,
          isLoading: false,
          feedbackHtml: '<p>Feedback</p>',
        });
      });
    });

    describe('while fetching feedback', () => {
      let resolveFeedback;

      beforeEach(async () => {
        const feedbackRequest = new Promise((resolve) => {
          resolveFeedback = resolve;
        });
        createComponent({
          glFeatures: { workplanScore: true },
          feedbackHandler: jest.fn().mockReturnValue(feedbackRequest),
        });
        await waitForPromises();
        await openDrawer();
      });

      it('keeps the drawer open and loading until the response arrives', async () => {
        expect(findReadiness().props()).toMatchObject({ isDrawerOpen: true, isLoading: true });
        expect(findWorkplan().props('isLoading')).toBe(false);

        resolveFeedback(feedbackResponse());
        await waitForPromises();

        expect(findReadiness().props()).toMatchObject({
          isDrawerOpen: true,
          isLoading: false,
          feedbackHtml: '<p>Feedback</p>',
        });
      });
    });

    describe('when the drawer closes before a feedback request fails', () => {
      beforeEach(async () => {
        let rejectFeedback;
        const feedbackRequest = new Promise((resolve, reject) => {
          rejectFeedback = reject;
        });
        createComponent({
          glFeatures: { workplanScore: true },
          feedbackHandler: jest.fn().mockReturnValue(feedbackRequest),
        });
        await waitForPromises();
        await openDrawer();
        await findReadiness().vm.$emit('close');
        await waitForPromises();
        rejectFeedback(new Error('feedback failed'));
        await waitForPromises();
      });

      it('ignores the outdated failure', () => {
        expect(findReadiness().props('hasError')).toBe(false);
        expect(createAlert).not.toHaveBeenCalled();
        expect(Sentry.captureException).not.toHaveBeenCalled();
      });
    });

    describe('when a workplan refetch fails while the drawer is open', () => {
      beforeEach(async () => {
        createComponent({
          glFeatures: { workplanScore: true },
          queryHandler: jest
            .fn()
            .mockResolvedValueOnce(workplanResponse({ readinessScore: 85 }))
            .mockRejectedValue(new Error('refetch failed')),
        });
        await waitForPromises();
        await openDrawer();
        await findWorkplan().vm.$emit('refetch-plan');
        await waitForPromises();
      });

      it('reports the workplan error on the page and keeps the feedback', () => {
        expect(createAlert).toHaveBeenCalledWith(
          expect.objectContaining({ error: expect.any(Error) }),
        );
        expect(findReadiness().props()).toMatchObject({
          hasError: false,
          feedbackHtml: '<p>Feedback</p>',
        });
      });
    });

    describe.each([false, true])('with feedback panel visibility %s', (isReadinessDrawerOpen) => {
      const queryHandler = jest.fn().mockResolvedValue(workplanResponse({ readinessScore: 85 }));

      beforeEach(async () => {
        createComponent({
          glFeatures: { workplanScore: true },
          queryHandler,
        });
        await waitForPromises();
        if (isReadinessDrawerOpen) {
          await openDrawer();
        }
      });

      it('keeps the workplan query variables independent of the drawer', () => {
        expect(queryHandler).toHaveBeenLastCalledWith({
          id: mockWorkItemId,
          useWorkItemFeatures: true,
          includeReadinessScore: true,
        });
      });

      it('passes drawer visibility alongside the score', () => {
        expect(findReadiness().props()).toMatchObject({
          workItemId: mockWorkItemId,
          score: 85,
          isDrawerOpen: isReadinessDrawerOpen,
        });
      });
    });

    describe('when the user opens readiness details', () => {
      beforeEach(async () => {
        createComponent({ glFeatures: { workplanScore: true } });
        await waitForPromises();
        findReadiness().vm.$emit('toggle');
      });

      it('opens the drawer without replacing the workplan panel', () => {
        expect(findReadiness().props('isDrawerOpen')).toBe(true);
        expect(wrapper.emitted('request-panel')).toBeUndefined();
      });
    });

    describe('when readiness details are already open', () => {
      beforeEach(async () => {
        createComponent({
          glFeatures: { workplanScore: true },
        });
        await waitForPromises();
        await findReadiness().vm.$emit('toggle');
      });

      it('toggles the drawer closed', async () => {
        await findReadiness().vm.$emit('toggle');
        expect(findReadiness().props('isDrawerOpen')).toBe(false);
      });
    });

    describe('after feedback has been loaded', () => {
      let feedbackHandler;

      beforeEach(async () => {
        feedbackHandler = jest.fn().mockResolvedValue(feedbackResponse());
        createComponent({ glFeatures: { workplanScore: true }, feedbackHandler });
        await waitForPromises();
        await openDrawer();
        await findReadiness().vm.$emit('close');
        await waitForPromises();
      });

      it('reopens cached feedback without another request or loading state', async () => {
        feedbackHandler.mockClear();
        await findReadiness().vm.$emit('toggle');

        expect(findReadiness().props()).toMatchObject({
          isDrawerOpen: true,
          isLoading: false,
          feedbackHtml: '<p>Feedback</p>',
        });
        await waitForPromises();
        expect(feedbackHandler).not.toHaveBeenCalled();
      });

      it('keeps the cached feedback next to the error when a refresh fails', async () => {
        await findReadiness().vm.$emit('toggle');
        feedbackHandler.mockRejectedValue(new Error('refresh failed'));
        await findReadiness().vm.$emit('retry');
        await waitForPromises();

        expect(findReadiness().props()).toMatchObject({
          hasError: true,
          isLoading: false,
          feedbackHtml: '<p>Feedback</p>',
        });
        expect(createAlert).not.toHaveBeenCalled();
      });
    });

    describe('when the readiness score changes after feedback has been loaded', () => {
      let queryHandler;
      let feedbackHandler;

      const refetchWorkplanWithScore = async (readinessScore) => {
        queryHandler.mockResolvedValue(workplanResponse({ readinessScore }));
        await findWorkplan().vm.$emit('refetch-plan');
        await waitForPromises();
      };

      beforeEach(async () => {
        queryHandler = jest.fn().mockResolvedValue(workplanResponse({ readinessScore: 85 }));
        feedbackHandler = jest.fn().mockResolvedValue(feedbackResponse());
        createComponent({ glFeatures: { workplanScore: true }, queryHandler, feedbackHandler });
        await waitForPromises();
        await openDrawer();
      });

      describe('while the drawer is closed', () => {
        beforeEach(async () => {
          await findReadiness().vm.$emit('close');
          await waitForPromises();
          feedbackHandler.mockClear();
          feedbackHandler.mockResolvedValue(feedbackResponse('<p>New feedback</p>'));
        });

        it('waits for the drawer to open before requesting feedback', async () => {
          await refetchWorkplanWithScore(40);

          expect(feedbackHandler).not.toHaveBeenCalled();
        });

        it('requests the new feedback once when the drawer reopens', async () => {
          await refetchWorkplanWithScore(40);
          await openDrawer();

          expect(feedbackHandler).toHaveBeenCalledTimes(1);
          expect(findReadiness().props('feedbackHtml')).toBe('<p>New feedback</p>');

          await findReadiness().vm.$emit('close');
          await openDrawer();

          expect(feedbackHandler).toHaveBeenCalledTimes(1);
        });

        it('reopens cached feedback when the score did not change', async () => {
          await refetchWorkplanWithScore(85);
          await openDrawer();

          expect(feedbackHandler).not.toHaveBeenCalled();
          expect(findReadiness().props('feedbackHtml')).toBe('<p>Feedback</p>');
        });
      });

      describe('while the drawer is open', () => {
        beforeEach(async () => {
          feedbackHandler.mockClear();
          feedbackHandler.mockResolvedValue(feedbackResponse('<p>New feedback</p>'));
          await refetchWorkplanWithScore(40);
        });

        it('requests the new feedback right away', () => {
          expect(feedbackHandler).toHaveBeenCalledTimes(1);
          expect(findReadiness().props('feedbackHtml')).toBe('<p>New feedback</p>');
        });
      });

      describe('while a feedback request is in flight', () => {
        let resolveFeedback;

        beforeEach(async () => {
          feedbackHandler.mockClear();
          feedbackHandler.mockReturnValueOnce(
            new Promise((resolve) => {
              resolveFeedback = resolve;
            }),
          );
          feedbackHandler.mockResolvedValue(feedbackResponse('<p>Newest feedback</p>'));
          await findReadiness().vm.$emit('retry');
          await refetchWorkplanWithScore(40);
        });

        it('requests the new feedback once the outdated request settles', async () => {
          expect(feedbackHandler).toHaveBeenCalledTimes(1);

          resolveFeedback(feedbackResponse('<p>Outdated feedback</p>'));
          await waitForPromises();

          expect(feedbackHandler).toHaveBeenCalledTimes(2);
          expect(findReadiness().props('feedbackHtml')).toBe('<p>Newest feedback</p>');
        });
      });
    });

    describe('when a run finishes', () => {
      let queryHandler;
      let feedbackHandler;

      const finishRunWithSameScore = async () => {
        queryHandler.mockResolvedValue(
          workplanResponse({ readinessScore: 85, generationStatus: 'COMPLETED' }),
        );
        await findWorkplan().vm.$emit('refetch-plan');
        await waitForPromises();
      };

      beforeEach(async () => {
        queryHandler = jest
          .fn()
          .mockResolvedValue(
            workplanResponse({ readinessScore: 85, generationStatus: 'GENERATING' }),
          );
        feedbackHandler = jest.fn().mockResolvedValue(feedbackResponse());
        createComponent({ glFeatures: { workplanScore: true }, queryHandler, feedbackHandler });
        await waitForPromises();
        await openDrawer();
        feedbackHandler.mockClear();
        feedbackHandler.mockResolvedValue(feedbackResponse('<p>New feedback</p>'));
      });

      it('requests the new feedback when the drawer reopens', async () => {
        await findReadiness().vm.$emit('close');
        await waitForPromises();
        await finishRunWithSameScore();

        expect(feedbackHandler).not.toHaveBeenCalled();

        await openDrawer();

        expect(feedbackHandler).toHaveBeenCalledTimes(1);
        expect(findReadiness().props('feedbackHtml')).toBe('<p>New feedback</p>');
      });

      it('requests the new feedback right away while the drawer is open', async () => {
        await finishRunWithSameScore();

        expect(feedbackHandler).toHaveBeenCalledTimes(1);
        expect(findReadiness().props('feedbackHtml')).toBe('<p>New feedback</p>');
      });

      it('requests the feedback once when the score changes as the run finishes', async () => {
        queryHandler.mockResolvedValue(
          workplanResponse({ readinessScore: 40, generationStatus: 'COMPLETED' }),
        );
        await findWorkplan().vm.$emit('refetch-plan');
        await waitForPromises();

        expect(feedbackHandler).toHaveBeenCalledTimes(1);
        expect(findReadiness().props('feedbackHtml')).toBe('<p>New feedback</p>');
      });
    });

    describe('inside a work item drawer', () => {
      beforeEach(async () => {
        createComponent({
          props: { isInDrawer: true, workItemWebUrl: '/group/project/-/work_items/1' },
          glFeatures: { workplanScore: true },
        });
        await waitForPromises();
      });

      it('opens the readiness drawer in place', async () => {
        await findReadiness().vm.$emit('toggle');
        expect(findReadiness().props('isDrawerOpen')).toBe(true);
      });
    });

    describe('when the workplanScore feature flag is disabled', () => {
      const queryHandler = jest.fn().mockResolvedValue(workplanResponse({ readinessScore: 85 }));

      beforeEach(async () => {
        createComponent({ glFeatures: { workplanScore: false }, queryHandler });
        await waitForPromises();
      });

      it('does not render the score', () => {
        expect(findReadiness().exists()).toBe(false);
      });

      it('does not request the score field', () => {
        expect(queryHandler).toHaveBeenCalledWith(
          expect.objectContaining({ includeReadinessScore: false }),
        );
      });
    });

    describe('when the workplanScore feature flag is enabled', () => {
      const queryHandler = jest.fn().mockResolvedValue(workplanResponse({ readinessScore: 85 }));

      beforeEach(async () => {
        createComponent({ glFeatures: { workplanScore: true }, queryHandler });
        await waitForPromises();
      });

      it('requests the score field', () => {
        expect(queryHandler).toHaveBeenCalledWith(
          expect.objectContaining({ includeReadinessScore: true }),
        );
      });

      it('renders the score', () => {
        expect(findReadiness().exists()).toBe(true);
      });

      it('passes the queried readiness score to the score component', () => {
        expect(findReadiness().props('score')).toBe(85);
      });
    });

    describe('when the flag is enabled but the query is still loading', () => {
      const queryHandler = jest.fn().mockResolvedValue(workplanResponse({ readinessScore: 85 }));

      it('does not render the score until the query settles', async () => {
        createComponent({ glFeatures: { workplanScore: true }, queryHandler });

        expect(findReadiness().exists()).toBe(false);

        await waitForPromises();

        expect(findReadiness().props('score')).toBe(85);
      });
    });

    describe('when the score is unavailable', () => {
      beforeEach(async () => {
        createComponent({
          glFeatures: { workplanScore: true },
          queryHandler: jest.fn().mockResolvedValue(workplanResponse({ readinessScore: null })),
        });
        await waitForPromises();
      });

      it('hides the readiness component and its panel trigger', () => {
        expect(findReadiness().exists()).toBe(false);
      });
    });

    describe('when the flag is enabled and the score is zero', () => {
      beforeEach(async () => {
        createComponent({
          glFeatures: { workplanScore: true },
          queryHandler: jest.fn().mockResolvedValue(workplanResponse({ readinessScore: 0 })),
        });
        await waitForPromises();
      });

      it('renders the score', () => {
        expect(findReadiness().props('score')).toBe(0);
      });
    });
  });

  describe('polling while a run is active', () => {
    // A subscription that never emits, so the poll is the only thing re-reading the plan.
    const mountWithStatus = async (generationStatus, { glFeatures } = {}) => {
      const queryHandler = jest
        .fn()
        .mockResolvedValue(workplanResponse({ readinessScore: 85, generationStatus }));
      createComponent({
        queryHandler,
        glFeatures,
        subscriptionHandler: jest.fn(() => new Promise(() => {})),
      });
      await waitForPromises();

      return queryHandler;
    };

    const advanceWorkplanPollTimer = async (intervals = 1) => {
      jest.advanceTimersByTime(ACTIVE_RUN_POLL_INTERVAL_MS * intervals);
      await waitForPromises();
    };

    beforeEach(() => {
      jest.useFakeTimers();
    });

    afterEach(() => {
      jest.useRealTimers();
    });

    describe('while the run is GENERATING', () => {
      it('re-reads the plan', async () => {
        const queryHandler = await mountWithStatus('GENERATING');

        expect(queryHandler).toHaveBeenCalledTimes(1);

        await advanceWorkplanPollTimer();

        expect(queryHandler).toHaveBeenCalledTimes(2);
      });
    });

    describe('while the run is NEEDS_INPUT', () => {
      describe('when the page loads with the run paused', () => {
        it('does not poll', async () => {
          const queryHandler = await mountWithStatus('NEEDS_INPUT');
          findWorkplan().vm.$emit('run-active', true);
          await waitForPromises();

          expect(queryHandler).toHaveBeenCalledTimes(1);

          await advanceWorkplanPollTimer(3);

          expect(queryHandler).toHaveBeenCalledTimes(1);
        });
      });

      describe('when Continue is clicked', () => {
        it('polls until the status moves on', async () => {
          const queryHandler = await mountWithStatus('NEEDS_INPUT');
          findWorkplan().vm.$emit('run-active', true);
          findWorkplan().vm.$emit('action-pending', true);
          await waitForPromises();

          expect(queryHandler).toHaveBeenCalledTimes(1);

          await advanceWorkplanPollTimer();

          expect(queryHandler).toHaveBeenCalledTimes(2);
        });
      });

      describe('when the Continue action is released without the status moving', () => {
        it('stops polling', async () => {
          const queryHandler = await mountWithStatus('NEEDS_INPUT');
          findWorkplan().vm.$emit('run-active', true);
          findWorkplan().vm.$emit('action-pending', true);
          await waitForPromises();
          findWorkplan().vm.$emit('action-pending', false);
          await waitForPromises();

          expect(queryHandler).toHaveBeenCalledTimes(1);

          await advanceWorkplanPollTimer(3);

          expect(queryHandler).toHaveBeenCalledTimes(1);
        });
      });
    });

    describe.each(['COMPLETED', 'CANCELED', 'FAILED', null])(
      'when the run has settled on %s',
      (generationStatus) => {
        it('does not poll', async () => {
          const queryHandler = await mountWithStatus(generationStatus);

          await advanceWorkplanPollTimer(3);

          expect(queryHandler).toHaveBeenCalledTimes(1);
        });
      },
    );

    // The refetch after a mutation is a single shot, so a stale read there would
    // otherwise leave a running flow with nothing watching it.
    it('polls while an action is in flight, even though the run still reads as settled', async () => {
      const queryHandler = await mountWithStatus('COMPLETED');
      await advanceWorkplanPollTimer();

      expect(queryHandler).toHaveBeenCalledTimes(1);

      findWorkplan().vm.$emit('run-active', true);
      await waitForPromises();
      await advanceWorkplanPollTimer();

      expect(queryHandler).toHaveBeenCalledTimes(2);
    });

    // Changing the workplan query's variables used to rebuild it without a numeric poll
    // interval, which polled back-to-back.
    describe.each([
      ['open', 1],
      ['opened and closed', 2],
    ])('after the readiness drawer is %s', (_, toggles) => {
      const toggleDrawer = async () => {
        for (let i = 0; i < toggles; i += 1) {
          // eslint-disable-next-line no-await-in-loop
          await findReadiness().vm.$emit('toggle');
          // eslint-disable-next-line no-await-in-loop
          await waitForPromises();
        }
      };

      it('does not poll a settled run', async () => {
        const queryHandler = await mountWithStatus('COMPLETED', {
          glFeatures: { workplanScore: true },
        });
        await toggleDrawer();
        await advanceWorkplanPollTimer(3);

        expect(queryHandler).toHaveBeenCalledTimes(1);
      });

      it('keeps polling an active run at the poll interval', async () => {
        const queryHandler = await mountWithStatus('GENERATING', {
          glFeatures: { workplanScore: true },
        });
        await toggleDrawer();
        await advanceWorkplanPollTimer();
        await advanceWorkplanPollTimer();

        expect(queryHandler).toHaveBeenCalledTimes(3);
      });
    });

    describe('with the readiness drawer open', () => {
      let queryHandler;

      beforeEach(async () => {
        queryHandler = await mountWithStatus('GENERATING', {
          glFeatures: { workplanScore: true },
        });
        await findReadiness().vm.$emit('toggle');
        await waitForPromises();
      });

      it('does not show the loading state for background polls', async () => {
        await advanceWorkplanPollTimer();

        expect(queryHandler).toHaveBeenCalledTimes(2);
        expect(findReadiness().props('isLoading')).toBe(false);
      });

      it('reports a failed poll on the page, not in the drawer', async () => {
        queryHandler.mockRejectedValue(new Error('poll failed'));
        await advanceWorkplanPollTimer();

        expect(findReadiness().props('hasError')).toBe(false);
        expect(createAlert).toHaveBeenCalled();
      });
    });
  });

  describe('implementation', () => {
    const sessionsResponse = (nodes) =>
      jest.fn().mockResolvedValue(buildWorkItemSessionsQueryResponse({ nodes }));

    const createImplementationComponent = (options) =>
      createComponent({ subscriptionHandler: jest.fn(() => createMockSubscription()), ...options });

    describe('when the work item is closed', () => {
      beforeEach(async () => {
        createImplementationComponent({ props: { workItem: { ...workItem, state: 'CLOSED' } } });
        await waitForPromises();
      });

      it('does not let the workplan run on a closed work item', () => {
        expect(findWorkplan().props('canRunWorkplan')).toBe(false);
      });

      it('lets the workplan run once the work item is reopened', async () => {
        await wrapper.setProps({ workItem: { ...workItem, state: 'OPEN' } });

        expect(findWorkplan().props('canRunWorkplan')).toBe(true);
      });

      it('does not offer Implement', () => {
        expect(findWorkplan().props('canImplement')).toBe(false);
      });

      it('offers Implement once the work item is reopened', async () => {
        await wrapper.setProps({ workItem: { ...workItem, state: 'OPEN' } });

        expect(findWorkplan().props('canImplement')).toBe(true);
      });
    });

    describe('when the work item has no Developer flow sessions', () => {
      beforeEach(async () => {
        createImplementationComponent({ sessionsHandler: sessionsResponse([workplanSession]) });
        await waitForPromises();
      });

      it('offers Implement', () => {
        expect(findWorkplan().props('canImplement')).toBe(true);
      });
    });

    describe('when the work item has a Developer flow session', () => {
      beforeEach(async () => {
        createImplementationComponent({
          sessionsHandler: sessionsResponse([developerSession, workplanSession]),
        });
        await waitForPromises();
      });

      it('does not offer Implement', () => {
        expect(findWorkplan().props('canImplement')).toBe(false);
      });
    });

    describe('when the latest Developer flow session was canceled', () => {
      beforeEach(async () => {
        createImplementationComponent({
          sessionsHandler: sessionsResponse([
            { ...developerSession, status: 'STOPPED', createdAt: '2026-01-16T09:00:00Z' },
            {
              ...developerSession,
              id: 'gid://gitlab/Ai::DuoWorkflows::Workflow/13',
              status: 'FINISHED',
            },
          ]),
        });
        await waitForPromises();
      });

      it('offers Implement again', () => {
        expect(findWorkplan().props('canImplement')).toBe(true);
      });
    });

    describe('when an earlier Developer flow session was canceled', () => {
      beforeEach(async () => {
        createImplementationComponent({
          sessionsHandler: sessionsResponse([
            { ...developerSession, status: 'STOPPED' },
            {
              ...developerSession,
              id: 'gid://gitlab/Ai::DuoWorkflows::Workflow/13',
              createdAt: '2026-01-16T09:00:00Z',
            },
          ]),
        });
        await waitForPromises();
      });

      it('does not offer Implement', () => {
        expect(findWorkplan().props('canImplement')).toBe(false);
      });
    });

    describe('when the workplan starts an implementation', () => {
      const createdSession = { ...developerSession, status: 'CREATED' };

      describe('while the new session is being fetched', () => {
        let sessionsHandler;

        beforeEach(async () => {
          sessionsHandler = jest
            .fn()
            .mockResolvedValueOnce(buildWorkItemSessionsQueryResponse({ nodes: [workplanSession] }))
            .mockReturnValueOnce(new Promise(() => {}));
          createImplementationComponent({ sessionsHandler });
          await waitForPromises();

          findWorkplan().vm.$emit('implementation-started');
          await nextTick();
        });

        it('fetches the sessions again', () => {
          expect(sessionsHandler).toHaveBeenCalledTimes(2);
        });

        it('does not offer Implement', () => {
          expect(findWorkplan().props('canImplement')).toBe(false);
        });
      });

      describe.each`
        scenario                          | nodes                                | expected
        ${'the new session arrives'}      | ${[createdSession, workplanSession]} | ${false}
        ${'no Developer session arrives'} | ${[workplanSession]}                 | ${true}
      `('when $scenario', ({ nodes, expected }) => {
        beforeEach(async () => {
          const sessionsHandler = jest
            .fn()
            .mockResolvedValueOnce(buildWorkItemSessionsQueryResponse({ nodes: [workplanSession] }))
            .mockResolvedValueOnce(buildWorkItemSessionsQueryResponse({ nodes }));
          createImplementationComponent({ sessionsHandler });
          await waitForPromises();

          findWorkplan().vm.$emit('implementation-started');
          await waitForPromises();
        });

        it(`sets canImplement to ${expected}`, () => {
          expect(findWorkplan().props('canImplement')).toBe(expected);
        });
      });

      describe('when the new session arrives', () => {
        beforeEach(async () => {
          const sessionsHandler = jest
            .fn()
            .mockResolvedValueOnce(buildWorkItemSessionsQueryResponse({ nodes: [workplanSession] }))
            .mockResolvedValueOnce(
              buildWorkItemSessionsQueryResponse({ nodes: [createdSession, workplanSession] }),
            );
          createImplementationComponent({ sessionsHandler });
          await waitForPromises();

          findWorkplan().vm.$emit('implementation-started');
          await waitForPromises();
        });

        it('keeps the cached workplan of the work item', () => {
          const { features } =
            apolloProvider.clients.defaultClient.cache.extract()[`WorkItem:${mockWorkItemId}`];

          expect(features.agentPlan).toMatchObject({ type: 'AGENT_PLAN' });
        });
      });
    });

    describe('when a Developer flow session starts after the page loads', () => {
      beforeEach(async () => {
        createImplementationComponent({ sessionsHandler: sessionsResponse([workplanSession]) });
        await waitForPromises();

        apolloProvider.clients.defaultClient.writeQuery({
          query: getDuoAgentSessionsOnWorkItemQuery,
          variables: { id: mockWorkItemId, first: 20 },
          data: buildWorkItemSessionsQueryResponse({ nodes: [developerSession, workplanSession] })
            .data,
        });
        await waitForPromises();
      });

      it('stops offering Implement without a refetch', () => {
        expect(findWorkplan().props('canImplement')).toBe(false);
      });
    });

    describe('while the sessions are loading', () => {
      beforeEach(() => {
        createImplementationComponent({ sessionsHandler: jest.fn(() => new Promise(() => {})) });
      });

      it('does not offer Implement yet', () => {
        expect(findWorkplan().props('canImplement')).toBe(false);
      });
    });

    describe('when the sessions query errors', () => {
      beforeEach(async () => {
        createImplementationComponent({
          sessionsHandler: jest.fn().mockRejectedValue(new Error()),
        });
        await waitForPromises();
      });

      it('reports the error and does not offer Implement', () => {
        expect(Sentry.captureException).toHaveBeenCalled();
        expect(findWorkplan().props('canImplement')).toBe(false);
      });

      it('offers Implement again once the Sessions widget loads them into the cache', async () => {
        apolloProvider.clients.defaultClient.writeQuery({
          query: getDuoAgentSessionsOnWorkItemQuery,
          variables: { id: mockWorkItemId, first: 20 },
          data: buildWorkItemSessionsQueryResponse({ nodes: [workplanSession] }).data,
        });
        await waitForPromises();

        expect(findWorkplan().props('canImplement')).toBe(true);
      });
    });
  });
});
