import { GlButton, GlDisclosureDropdown, GlDisclosureDropdownItem } from '@gitlab/ui';
import Vue, { nextTick } from 'vue';
import VueApollo from 'vue-apollo';
import WorkplanAvailabilityPopover from 'ee/work_items/components/implementation_widget/workplan_availability_popover.vue';
import createMockApollo from 'helpers/mock_apollo_helper';
import waitForPromises from 'helpers/wait_for_promises';
import { shallowMountExtended } from 'helpers/vue_test_utils_helper';
import { stubComponent } from 'helpers/stub_component';
import { useMockInternalEventsTracking } from 'helpers/tracking_internal_events_helper';
import setWindowLocation from 'helpers/set_window_location_helper';
import { visitUrl } from '~/lib/utils/url_utility';
import * as Sentry from '~/sentry/sentry_browser_wrapper';
import WorkItemPlanCta from 'ee/work_items/components/work_item_plan_cta.vue';
import DuoWorkItemToMrAction from 'ee/ai/shared/widgets/duo_work_item_to_mr_action.vue';
import workItemEnableAiPlanningMutation from 'ee/work_items/graphql/work_item_enable_ai_planning.mutation.graphql';
import workItemGenerateWorkplanMutation from 'ee/work_items/graphql/work_item_generate_workplan.mutation.graphql';
import workplanFlowAvailabilityQuery from 'ee/work_items/graphql/workplan_flow_availability.query.graphql';
import {
  buildAgentPlanWidgetMock,
  buildWorkplanFlowAvailabilityResponse,
  buildWorkplanFlowMutationResponse,
} from 'ee_else_ce_jest/work_items/mock_data';
import { consumeWorkplanStartRequest } from 'ee/work_items/components/implementation_widget/workplan_start_request';

jest.mock('~/sentry/sentry_browser_wrapper');
// Mocked so the drawer redirect does not navigate jsdom.
jest.mock('~/lib/utils/url_utility', () => ({
  ...jest.requireActual('~/lib/utils/url_utility'),
  visitUrl: jest.fn(),
}));

Vue.use(VueApollo);

describe('WorkItemPlanCta component', () => {
  let wrapper;
  const { bindInternalEventDocument } = useMockInternalEventsTracking();

  const mockWorkItemId = 'gid://gitlab/WorkItem/1';

  const mockProjectPath = 'gitlab-org/gitlab';

  const mockWebUrl = '/gitlab-org/gitlab/-/work_items/1';

  const buildWorkItem = ({ useFeatures = false } = {}) => ({
    id: mockWorkItemId,
    iid: '1',
    webUrl: mockWebUrl,
    workItemType: { name: 'Issue' },
    namespace: { id: 'gid://gitlab/Namespaces::ProjectNamespace/1', fullPath: mockProjectPath },
    ...(useFeatures
      ? { features: { agentPlan: buildAgentPlanWidgetMock() } }
      : { widgets: [buildAgentPlanWidgetMock()] }),
  });

  const successMutationHandler = jest.fn().mockResolvedValue({
    data: {
      workItemEnableAiPlanning: {
        __typename: 'WorkItemEnableAiPlanningPayload',
        workItem: null,
        errors: [],
      },
    },
  });

  const generateHandlerFor = (options) =>
    jest
      .fn()
      .mockResolvedValue(buildWorkplanFlowMutationResponse('workItemGenerateWorkplan', options));

  const createComponent = ({
    workItem = buildWorkItem(),
    mutationHandler = successMutationHandler,
    generateHandler = generateHandlerFor(),
    availabilityHandler = jest.fn().mockResolvedValue(buildWorkplanFlowAvailabilityResponse()),
    isInDrawer = false,
    openDetailPanelItemPage = null,
  } = {}) => {
    wrapper = shallowMountExtended(WorkItemPlanCta, {
      apolloProvider: createMockApollo([
        [workItemEnableAiPlanningMutation, mutationHandler],
        [workItemGenerateWorkplanMutation, generateHandler],
        [workplanFlowAvailabilityQuery, availabilityHandler],
      ]),
      propsData: { workItem, isInDrawer },
      provide: { openDetailPanelItemPage },
      stubs: { GlDisclosureDropdown: stubComponent(GlDisclosureDropdown) },
    });
  };

  const findPlanButton = () => wrapper.findComponent(GlButton);
  const findPopover = () => wrapper.findComponent(WorkplanAvailabilityPopover);
  const findDropdown = () => wrapper.findComponent(GlDisclosureDropdown);
  const findCreateManuallyItem = () => findDropdown().findComponent(GlDisclosureDropdownItem);
  const findImplementAction = () => findDropdown().findComponent(DuoWorkItemToMrAction);
  const selectCreateManually = () => findCreateManuallyItem().vm.$emit('action');

  beforeEach(() => {
    successMutationHandler.mockClear();
    consumeWorkplanStartRequest(mockWorkItemId);
  });

  describe('plan action tracking', () => {
    describe.each`
      outcome                    | mutationHandler
      ${'planning is enabled'}   | ${successMutationHandler}
      ${'enabling is refused'}   | ${jest.fn().mockResolvedValue({ data: { workItemEnableAiPlanning: { __typename: 'WorkItemEnableAiPlanningPayload', workItem: null, errors: ['Not allowed'] } } })}
      ${'the enable call fails'} | ${jest.fn().mockRejectedValue(new Error('Network error'))}
    `('when $outcome', ({ mutationHandler }) => {
      let trackEventSpy;

      beforeEach(async () => {
        ({ trackEventSpy } = bindInternalEventDocument());
        createComponent({ mutationHandler });
        findPlanButton().vm.$emit('click');
        await waitForPromises();
      });

      it('tracks the plan action once', () => {
        expect(trackEventSpy).toHaveBeenCalledTimes(1);
        expect(trackEventSpy).toHaveBeenCalledWith(
          'click_work_item_workplan_action',
          { label: 'plan', property: 'plan_cta' },
          undefined,
        );
      });
    });
  });

  describe('when clicking the button', () => {
    beforeEach(async () => {
      createComponent();
      // Let the availability query confirm the project first, as in the main path.
      await waitForPromises();
      findPlanButton().vm.$emit('click');
      await waitForPromises();
    });

    it('fires the mutation with the work item id', () => {
      expect(successMutationHandler).toHaveBeenCalledWith(
        expect.objectContaining({
          input: { id: mockWorkItemId },
        }),
      );
    });

    describe('when the work item has features', () => {
      beforeEach(async () => {
        createComponent({
          workItem: buildWorkItem({ useFeatures: true }),
        });
        findPlanButton().vm.$emit('click');
        await waitForPromises();
      });

      it('passes useWorkItemFeatures to the mutation', () => {
        expect(successMutationHandler).toHaveBeenCalledWith(
          expect.objectContaining({ useWorkItemFeatures: true }),
        );
      });
    });

    describe('when the mutation returns errors', () => {
      beforeEach(async () => {
        const mutationHandler = jest.fn().mockResolvedValue({
          data: {
            workItemEnableAiPlanning: {
              __typename: 'WorkItemEnableAiPlanningPayload',
              workItem: null,
              errors: ['AI planning is not available for this work item'],
            },
          },
        });
        createComponent({ mutationHandler });
        findPlanButton().vm.$emit('click');
        await waitForPromises();
      });

      it('emits the backend reason', () => {
        expect(wrapper.emitted('error')).toEqual([
          ['AI planning is not available for this work item'],
        ]);
        expect(Sentry.captureException).not.toHaveBeenCalled();
      });
    });

    describe('when the mutation rejects', () => {
      beforeEach(async () => {
        const mutationHandler = jest.fn().mockRejectedValue(new Error('network error'));
        createComponent({ mutationHandler });
        findPlanButton().vm.$emit('click');
        await waitForPromises();
      });

      it('emits the generic error and reports to Sentry', () => {
        expect(wrapper.emitted('error')).toEqual([
          ['Something went wrong while enabling planning for this item. Please try again.'],
        ]);
        expect(Sentry.captureException).toHaveBeenCalled();
      });
    });

    describe('when the mutation fails without a message', () => {
      beforeEach(async () => {
        const mutationHandler = jest.fn().mockRejectedValue(new Error());
        createComponent({ mutationHandler });
        findPlanButton().vm.$emit('click');
        await waitForPromises();
      });

      it('emits the generic fallback and reports to Sentry', () => {
        expect(wrapper.emitted('error')).toEqual([
          ['Something went wrong while enabling planning for this item. Please try again.'],
        ]);
        expect(Sentry.captureException).toHaveBeenCalled();
      });
    });
  });

  describe('while enabling planning is pending', () => {
    let mutationHandler;

    beforeEach(async () => {
      mutationHandler = jest.fn().mockReturnValue(new Promise(() => {}));
      createComponent({ mutationHandler });
      findPlanButton().vm.$emit('click');
      await nextTick();
    });

    it('disables the button, without a loading state', () => {
      expect(findPlanButton().props('loading')).toBe(false);
      expect(findPlanButton().props('disabled')).toBe(true);
    });

    describe('when clicked again', () => {
      beforeEach(async () => {
        findPlanButton().vm.$emit('click');
        await waitForPromises();
      });

      it('does not enable planning twice', () => {
        expect(mutationHandler).toHaveBeenCalledTimes(1);
      });
    });
  });

  describe('starting the workplan run', () => {
    describe('when planning is enabled', () => {
      let generateHandler;

      beforeEach(async () => {
        generateHandler = generateHandlerFor();
        createComponent({ generateHandler });
        findPlanButton().vm.$emit('click');
        await waitForPromises();
      });

      it('does not start the run itself', () => {
        expect(generateHandler).not.toHaveBeenCalled();
      });

      it('leaves a start request for the workplan widget', () => {
        expect(consumeWorkplanStartRequest(mockWorkItemId)).toBe(true);
      });
    });

    describe('while planning is being enabled', () => {
      let requestedBeforeEnable;

      beforeEach(async () => {
        createComponent({
          mutationHandler: jest.fn().mockImplementation(() => {
            requestedBeforeEnable = consumeWorkplanStartRequest(mockWorkItemId);
            return successMutationHandler();
          }),
        });
        findPlanButton().vm.$emit('click');
        await waitForPromises();
      });

      it('has already registered the start request', () => {
        expect(requestedBeforeEnable).toBe(true);
      });
    });

    describe.each`
      outcome      | mutationHandler
      ${'refused'} | ${jest.fn().mockResolvedValue({ data: { workItemEnableAiPlanning: { __typename: 'WorkItemEnableAiPlanningPayload', workItem: null, errors: ['Not allowed'] } } })}
      ${'fails'}   | ${jest.fn().mockRejectedValue(new Error('network error'))}
    `('when enabling planning $outcome', ({ mutationHandler }) => {
      beforeEach(async () => {
        createComponent({ mutationHandler });
        findPlanButton().vm.$emit('click');
        await waitForPromises();
      });

      it('cancels the start request', () => {
        expect(consumeWorkplanStartRequest(mockWorkItemId)).toBe(false);
      });
    });

    describe('when creating manually', () => {
      beforeEach(async () => {
        setWindowLocation('http://test.host/gitlab-org/gitlab/-/work_items/1');
        createComponent();
        selectCreateManually();
        await waitForPromises();
      });

      it('does not register a start request', () => {
        expect(consumeWorkplanStartRequest(mockWorkItemId)).toBe(false);
      });
    });
  });

  describe('availability', () => {
    it('requests project availability with the project path', async () => {
      const availabilityHandler = jest
        .fn()
        .mockResolvedValue(buildWorkplanFlowAvailabilityResponse());
      createComponent({ availabilityHandler });
      await waitForPromises();

      expect(availabilityHandler).toHaveBeenCalledWith({ fullPath: mockProjectPath });
    });

    it('keeps Plan enabled while availability is loading', () => {
      createComponent({ availabilityHandler: jest.fn().mockReturnValue(new Promise(() => {})) });

      expect(findPlanButton().props('disabled')).toBe(false);
      expect(findPopover().exists()).toBe(false);
    });

    it('keeps Plan enabled when the project is configured', async () => {
      createComponent();
      await waitForPromises();

      expect(findPlanButton().props('disabled')).toBe(false);
      expect(findPopover().exists()).toBe(false);
    });

    describe.each`
      setting                 | overrides
      ${'GitLab Duo'}         | ${{ duoFeaturesEnabled: false }}
      ${'flow execution'}     | ${{ remoteFlowsEnabled: false }}
      ${'foundational flows'} | ${{ foundationalFlowsEnabled: false }}
      ${'Generate Workplan'}  | ${{ enabledFoundationalFlows: ['developer/v1'] }}
    `('when $setting is off for the project', ({ overrides }) => {
      let generateHandler;

      beforeEach(async () => {
        generateHandler = generateHandlerFor();
        createComponent({
          generateHandler,
          availabilityHandler: jest
            .fn()
            .mockResolvedValue(buildWorkplanFlowAvailabilityResponse(overrides)),
        });
        await waitForPromises();
      });

      it('disables Plan and explains the project configuration', () => {
        expect(findPlanButton().props()).toMatchObject({
          disabled: true,
          accessibleDisabled: true,
        });
        expect(findPopover().props('reason')).toBe(
          "Workplan generation isn't turned on for this project.",
        );
      });

      it('does not start a flow or enable planning', async () => {
        findPlanButton().vm.$emit('click');
        await waitForPromises();

        expect(generateHandler).not.toHaveBeenCalled();
        expect(successMutationHandler).not.toHaveBeenCalled();
      });
    });

    describe('when the availability query fails', () => {
      beforeEach(async () => {
        createComponent({
          availabilityHandler: jest.fn().mockRejectedValue(new Error('Network error')),
        });
        await waitForPromises();
      });

      it('keeps Plan enabled', () => {
        expect(findPlanButton().props('disabled')).toBe(false);
        expect(findPopover().exists()).toBe(false);
      });

      it('reports the error to Sentry', () => {
        expect(Sentry.captureException).toHaveBeenCalled();
      });
    });
  });

  describe('more planning options dropdown', () => {
    it('renders a split dropdown next to Plan, in the default button style', () => {
      createComponent();

      expect(findPlanButton().props()).toMatchObject({ category: 'primary', variant: 'default' });
      expect(findDropdown().props()).toMatchObject({
        toggleText: 'More planning options',
        textSrOnly: true,
        category: 'primary',
        variant: 'default',
        size: 'small',
        disabled: false,
        loading: false,
      });
      expect(findCreateManuallyItem().props('item')).toMatchObject({
        text: 'Create workplan manually',
        icon: 'doc-new',
      });
    });

    it('disables the dropdown while Plan is in flight', async () => {
      createComponent({ mutationHandler: jest.fn().mockReturnValue(new Promise(() => {})) });

      findPlanButton().vm.$emit('click');
      await nextTick();

      expect(findDropdown().props('disabled')).toBe(true);
    });
  });

  describe('create manually', () => {
    beforeEach(() => {
      setWindowLocation('http://test.host/gitlab-org/gitlab/-/work_items/1');
    });

    describe('when planning turns on', () => {
      let generateHandler;
      let trackEventSpy;

      beforeEach(async () => {
        ({ trackEventSpy } = bindInternalEventDocument());
        generateHandler = generateHandlerFor();
        createComponent({ generateHandler });
        selectCreateManually();
        await waitForPromises();
      });

      it('enables planning without generating a workplan', () => {
        expect(successMutationHandler).toHaveBeenCalledWith(
          expect.objectContaining({ input: { id: mockWorkItemId } }),
        );
        expect(generateHandler).not.toHaveBeenCalled();
      });

      it('asks the widget to open the workplan in edit mode', () => {
        expect(window.location.search).toBe('?show=workplan&workplan_state=edit');
        expect(visitUrl).not.toHaveBeenCalled();
      });

      it('tracks Create manually from the Plan dropdown, but no plan action', () => {
        expect(trackEventSpy).toHaveBeenCalledTimes(1);
        expect(trackEventSpy).toHaveBeenCalledWith('click_work_item_workplan_create_manually', {
          property: 'plan_cta',
        });
      });

      it('does not emit an error', () => {
        expect(wrapper.emitted('error')).toBeUndefined();
      });
    });

    it('writes the edit intent before enabling planning mounts the widget', async () => {
      let searchWhenEnabling;
      const mutationHandler = jest.fn().mockImplementation(() => {
        searchWhenEnabling = window.location.search;
        return successMutationHandler();
      });
      createComponent({ mutationHandler });

      selectCreateManually();
      await waitForPromises();

      expect(searchWhenEnabling).toBe('?show=workplan&workplan_state=edit');
    });

    it('shows the dropdown as loading and disables Plan while in flight', async () => {
      createComponent({ mutationHandler: jest.fn().mockReturnValue(new Promise(() => {})) });

      selectCreateManually();
      await nextTick();

      expect(findDropdown().props('loading')).toBe(true);
      expect(findPlanButton().props()).toMatchObject({ disabled: true, loading: false });
    });

    it('stays available when workplan generation is off for the project', async () => {
      createComponent({
        availabilityHandler: jest
          .fn()
          .mockResolvedValue(buildWorkplanFlowAvailabilityResponse({ remoteFlowsEnabled: false })),
      });
      await waitForPromises();

      expect(findPlanButton().props('disabled')).toBe(true);
      expect(findDropdown().props('disabled')).toBe(false);

      selectCreateManually();
      await waitForPromises();

      expect(successMutationHandler).toHaveBeenCalled();
    });

    describe('when in the drawer', () => {
      beforeEach(async () => {
        setWindowLocation('http://test.host/gitlab-org/gitlab/-/work_items?show=abc');
        createComponent({ isInDrawer: true });
        selectCreateManually();
        await waitForPromises();
      });

      it('keeps the drawer URL', () => {
        expect(window.location.search).toBe('?show=abc');
      });

      it('opens the workplan in edit mode on the work item page', () => {
        expect(visitUrl).toHaveBeenCalledWith(
          '/gitlab-org/gitlab/-/work_items/1?show=workplan&workplan_state=edit',
        );
      });
    });

    describe('when in a drawer that can open the work item page', () => {
      let openDetailPanelItemPage;

      beforeEach(async () => {
        setWindowLocation('http://test.host/gitlab-org/gitlab/-/work_items?show=abc');
        openDetailPanelItemPage = jest.fn();
        createComponent({ isInDrawer: true, openDetailPanelItemPage });
        selectCreateManually();
        await waitForPromises();
      });

      it('asks the drawer to open the workplan in edit mode, without a reload', () => {
        expect(openDetailPanelItemPage).toHaveBeenCalledWith({
          show: 'workplan',
          workplan_state: 'edit',
        });
        expect(visitUrl).not.toHaveBeenCalled();
      });
    });

    describe('when enabling planning returns errors', () => {
      beforeEach(async () => {
        const mutationHandler = jest.fn().mockResolvedValue({
          data: {
            workItemEnableAiPlanning: {
              __typename: 'WorkItemEnableAiPlanningPayload',
              workItem: null,
              errors: ['AI planning is not available for this work item'],
            },
          },
        });
        createComponent({ mutationHandler });
        selectCreateManually();
        await waitForPromises();
      });

      it('emits the backend reason', () => {
        expect(wrapper.emitted('error')).toEqual([
          ['AI planning is not available for this work item'],
        ]);
      });

      it('removes the edit intent from the URL', () => {
        expect(window.location.search).toBe('');
      });
    });

    describe('when enabling planning rejects', () => {
      beforeEach(async () => {
        createComponent({
          mutationHandler: jest.fn().mockRejectedValue(new Error('network error')),
        });
        selectCreateManually();
        await waitForPromises();
      });

      it('emits the generic error and reports to Sentry', () => {
        expect(wrapper.emitted('error')).toEqual([
          ['Something went wrong while enabling planning for this item. Please try again.'],
        ]);
        expect(Sentry.captureException).toHaveBeenCalled();
      });

      it('removes the edit intent from the URL', () => {
        expect(window.location.search).toBe('');
      });
    });

    describe('when in the drawer and enabling planning fails', () => {
      beforeEach(async () => {
        setWindowLocation('http://test.host/gitlab-org/gitlab/-/work_items?show=abc');
        createComponent({
          isInDrawer: true,
          mutationHandler: jest.fn().mockRejectedValue(new Error('network error')),
        });
        selectCreateManually();
        await waitForPromises();
      });

      it('stays in the drawer', () => {
        expect(visitUrl).not.toHaveBeenCalled();
        expect(window.location.search).toBe('?show=abc');
      });
    });
  });

  describe('implement', () => {
    it('does not track anything before Implement is clicked', async () => {
      const { trackEventSpy } = bindInternalEventDocument();
      createComponent();
      await waitForPromises();

      expect(trackEventSpy).not.toHaveBeenCalled();
    });

    it('offers Implement for the work item, with the unavailable reason and help link', () => {
      createComponent();

      expect(findImplementAction().props()).toMatchObject({
        projectPath: mockProjectPath,
        workItemIid: '1',
        workItemType: 'Issue',
        workItemWebUrl: mockWebUrl,
      });
      expect(findImplementAction().attributes()).toMatchObject({
        'render-as': 'dropdown-item',
        'disabled-flow-message': "Implementation with GitLab Duo isn't turned on for this project.",
        'disabled-flow-help-path': expect.stringContaining(
          'user/work_items/workplan#implement-a-work-item-without-a-workplan',
        ),
      });
    });

    it('lists Create workplan manually first and Implement last', () => {
      createComponent();

      expect([...findDropdown().element.children]).toEqual([
        findCreateManuallyItem().element,
        findImplementAction().element,
      ]);
    });

    it('stays offered when workplan generation is off for the project', async () => {
      createComponent({
        availabilityHandler: jest
          .fn()
          .mockResolvedValue(buildWorkplanFlowAvailabilityResponse({ duoFeaturesEnabled: false })),
      });
      await waitForPromises();

      expect(findPlanButton().props('disabled')).toBe(true);
      expect(findImplementAction().exists()).toBe(true);
    });

    describe('while the flow starts', () => {
      let trackEventSpy;

      beforeEach(async () => {
        ({ trackEventSpy } = bindInternalEventDocument());
        createComponent();
        findImplementAction().vm.$emit('triggering');
        await nextTick();
      });

      it('tracks the Implement click from the Plan dropdown without a readiness score', () => {
        expect(trackEventSpy).toHaveBeenCalledTimes(1);
        expect(trackEventSpy).toHaveBeenCalledWith('click_work_item_workplan_implement', {
          property: 'plan_cta',
        });
      });

      it('shows the dropdown as loading and disables Plan', () => {
        expect(findDropdown().props('loading')).toBe(true);
        expect(findPlanButton().props()).toMatchObject({ disabled: true, loading: false });
      });
    });

    describe.each`
      outcome                    | events
      ${'the flow starts'}       | ${['triggering', 'agent-flow-started', 'triggered']}
      ${'the flow cannot start'} | ${['triggering', 'triggered']}
    `('when $outcome', ({ events }) => {
      let generateHandler;

      beforeEach(async () => {
        generateHandler = generateHandlerFor();
        createComponent({ generateHandler });
        events.forEach((event) => findImplementAction().vm.$emit(event, { id: 7 }));
        await waitForPromises();
      });

      // Turning planning on would hide Plan and Implement, so a failed run couldn't be retried.
      it('leaves planning off and does not generate a workplan', () => {
        expect(successMutationHandler).not.toHaveBeenCalled();
        expect(generateHandler).not.toHaveBeenCalled();
      });

      it('releases the dropdown and Plan', () => {
        expect(findDropdown().props('loading')).toBe(false);
        expect(findPlanButton().props('disabled')).toBe(false);
      });
    });
  });
});
