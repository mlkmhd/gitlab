import { GlLoadingIcon } from '@gitlab/ui';
import Vue from 'vue';
import VueApollo from 'vue-apollo';
import { shallowMountExtended } from 'helpers/vue_test_utils_helper';
import createMockApollo from 'helpers/mock_apollo_helper';
import waitForPromises from 'helpers/wait_for_promises';
import { useMockInternalEventsTracking } from 'helpers/tracking_internal_events_helper';
import * as Sentry from '~/sentry/sentry_browser_wrapper';
import BoardView from '~/work_items/board/board_view.vue';
import BoardColumn from '~/work_items/board/components/board_column.vue';
import CreateWorkItemModal from '~/work_items/components/create_work_item_modal.vue';
import * as grouping from '~/work_items/board/grouping';
import { RELATIVE_POSITION_ASC } from '~/work_items/list/constants';
import {
  addWorkItemToColumn,
  adjustWorkItemCountInColumn,
  readWorkItemConnectionFromColumn,
  readWorkItemFromColumn,
  removeWorkItemFromColumn,
} from '~/work_items/board/graphql/cache_updates';
import getBoardWorkItemsQuery from 'ee_else_ce/work_items/board/graphql/get_board_work_items.query.graphql';
import getWorkItemsRestQuery from 'ee_else_ce/work_items/list/graphql/get_work_items_rest.query.graphql';
import {
  buildAllowedStatusesResponse,
  buildWorkItemTypesResponse,
  buildBoardRestWorkItemsResponse,
  buildBoardWorkItemsResponse,
  buildWorkItemNode,
  buildStatus,
  mockStatus,
} from './mock_data';

jest.mock('~/sentry/sentry_browser_wrapper');
jest.mock('~/work_items/board/graphql/cache_updates');

const { groupingStrategyFor } = grouping;

Vue.use(VueApollo);

describe('BoardView', () => {
  let wrapper;

  const groupValuesHandler = jest.fn();
  const gateDataHandler = jest.fn();
  // CE and EE use different queries here (CE has a placeholder, EE has the real
  // status queries), so pull them from whichever strategy the board actually resolves.
  const { valuesQuery: groupValuesQuery, gateQuery } = groupingStrategyFor('status');

  const queryVariables = { state: 'opened', sort: 'CREATED_DESC' };

  const findLoadingIcon = () => wrapper.findComponent(GlLoadingIcon);
  const findBoardColumns = () => wrapper.findAllComponents(BoardColumn);
  const findAllGroupsHiddenPrompt = () => wrapper.findComponentByTestId('all-groups-hidden-prompt');

  let apolloProvider;

  const createComponent = ({
    props = {},
    visibleGroups = null,
    visibleGroupsLoaded = true,
    glFeatures = {},
    duoRemoteFlowsAvailability = false,
    handlers = [],
  } = {}) => {
    apolloProvider = createMockApollo([
      [groupValuesQuery, groupValuesHandler],
      // In EE both are the same query, so one handler answers for both.
      ...(gateQuery && gateQuery !== groupValuesQuery ? [[gateQuery, gateDataHandler]] : []),
      ...handlers,
    ]);

    wrapper = shallowMountExtended(BoardView, {
      apolloProvider,
      provide: {
        glFeatures,
        duoRemoteFlowsAvailability,
      },
      propsData: {
        rootPageFullPath: 'full/path',
        queryVariables,
        // `true` by default so the group values query fires immediately, matching
        // the common case in tests below that aren't specifically about loading.
        visibleGroups,
        visibleGroupsLoaded,
        ...props,
      },
    });
  };

  beforeEach(() => {
    groupValuesHandler.mockResolvedValue(buildAllowedStatusesResponse([]));
    gateDataHandler.mockResolvedValue(buildWorkItemTypesResponse());
  });

  // Statuses don't exist in CE, so the placeholder strategy extracts no values
  // and the board just renders no columns. That's correct behavior, not a bug.
  describe('grouping by status', () => {
    it('renders no column groups', async () => {
      createComponent();
      await waitForPromises();

      expect(findBoardColumns()).toHaveLength(0);
    });

    it('renders no loading icon once settled', async () => {
      createComponent();
      await waitForPromises();

      expect(findLoadingIcon().exists()).toBe(false);
    });

    it('reports no error', async () => {
      createComponent();
      await waitForPromises();

      expect(Sentry.captureException).not.toHaveBeenCalled();
      expect(wrapper.emitted('set-error')).toBeUndefined();
    });
  });

  describe('tracking', () => {
    const { bindInternalEventDocument } = useMockInternalEventsTracking();

    it('tracks the board being viewed on mount, labelled with the grouping attribute', async () => {
      createComponent();
      await waitForPromises();
      const { trackEventSpy } = bindInternalEventDocument(wrapper.element);

      expect(trackEventSpy).toHaveBeenCalledTimes(1);
      expect(trackEventSpy).toHaveBeenCalledWith(
        'view_work_item_board',
        { label: 'status' },
        undefined,
      );
    });

    it('does not track again when props change', async () => {
      createComponent();
      await waitForPromises();
      const { trackEventSpy } = bindInternalEventDocument(wrapper.element);

      await wrapper.setProps({ collapsedGroups: ['status:1'] });
      await waitForPromises();

      expect(trackEventSpy).toHaveBeenCalledTimes(1);
    });
  });

  describe('when a work item is created on the board', () => {
    const createdWorkItem = buildWorkItemNode(42);

    const requestCreate = async () => {
      wrapper.findComponent(BoardColumn).vm.$emit('create-item', mockStatus);
      await waitForPromises();
      wrapper.findComponent(CreateWorkItemModal).vm.$emit('work-item-created', createdWorkItem);
      await waitForPromises();
    };

    beforeEach(() => {
      jest.spyOn(grouping, 'groupingStrategyFor').mockReturnValue({
        property: 'status',
        valuesQuery: groupValuesQuery,
        extractValues: () => [mockStatus],
        groupFilter: (value) => ({ status: { name: value.name } }),
        headerDecoration: () => ({ type: 'none' }),
        moveInput: () => ({}),
        newItemDraft: () => ({}),
        patchCard: () => {},
        itemValueId: () => mockStatus.id,
      });
      groupValuesHandler.mockResolvedValue(buildAllowedStatusesResponse([mockStatus]));
    });

    it.each`
      isGroup  | hideNamespaceSelector
      ${true}  | ${false}
      ${false} | ${true}
    `(
      'passes hideNamespaceSelector as $hideNamespaceSelector to the modal when queryVariables.isGroup is $isGroup',
      async ({ isGroup, hideNamespaceSelector }) => {
        createComponent({ props: { queryVariables: { ...queryVariables, isGroup } } });
        await waitForPromises();
        wrapper.findComponent(BoardColumn).vm.$emit('create-item', mockStatus);
        await waitForPromises();

        expect(wrapper.findComponent(CreateWorkItemModal).props('hideNamespaceSelector')).toBe(
          hideNamespaceSelector,
        );
      },
    );

    it.each`
      flag     | duoAvailable | expected
      ${true}  | ${true}      | ${true}
      ${true}  | ${false}     | ${false}
      ${false} | ${true}      | ${false}
    `(
      'passes includeAiSessions=$expected to the columns when the flag is $flag and Duo remote flows are $duoAvailable',
      async ({ flag, duoAvailable, expected }) => {
        createComponent({
          glFeatures: { planningViewBoardAiSessions: flag },
          duoRemoteFlowsAvailability: duoAvailable,
        });
        await waitForPromises();

        expect(wrapper.findComponent(BoardColumn).props('includeAiSessions')).toBe(expected);
      },
    );

    it('inserts the created item using the REST query when the flag is enabled', async () => {
      const restQueryHandler = jest
        .fn()
        .mockResolvedValue(buildBoardRestWorkItemsResponse([createdWorkItem]));
      createComponent({
        glFeatures: { workItemRestApiFrontendUsers: true },
        handlers: [[getWorkItemsRestQuery, restQueryHandler]],
      });
      await waitForPromises();

      await requestCreate();

      expect(addWorkItemToColumn).toHaveBeenCalledWith(
        expect.objectContaining({ query: getWorkItemsRestQuery, useRestApi: true }),
      );
    });

    it('inserts the created item using the GraphQL query when the flag is disabled', async () => {
      const boardQueryHandler = jest
        .fn()
        .mockResolvedValue(buildBoardWorkItemsResponse([createdWorkItem]));
      createComponent({
        glFeatures: { workItemRestApiFrontendUsers: false },
        handlers: [[getBoardWorkItemsQuery, boardQueryHandler]],
      });
      await waitForPromises();

      await requestCreate();

      expect(addWorkItemToColumn).toHaveBeenCalledWith(
        expect.objectContaining({ query: getBoardWorkItemsQuery, useRestApi: false }),
      );
    });
  });

  describe('when realtime changes are matched for items already on the board', () => {
    const createdMatch = buildWorkItemNode(43);
    const updatedMatch = buildWorkItemNode(44);
    const otherStatus = buildStatus(2, 'Doing');

    // Matches the shape `handleWorkItemCreated`'s tests use above, except `itemValueId`
    // is parameterized so a test can target either column.
    const fakeStrategy = (targetStatusId) => ({
      property: 'status',
      valuesQuery: groupValuesQuery,
      extractValues: () => [mockStatus, otherStatus],
      groupFilter: (value) => ({ status: { name: value.name } }),
      headerDecoration: () => ({ type: 'none' }),
      moveInput: () => ({}),
      newItemDraft: () => ({}),
      patchCard: () => {},
      itemValueId: () => targetStatusId,
    });

    beforeEach(() => {
      groupValuesHandler.mockResolvedValue(buildAllowedStatusesResponse([mockStatus, otherStatus]));
    });

    it('inserts a matched created item into the column its grouped value points to', async () => {
      jest.spyOn(grouping, 'groupingStrategyFor').mockReturnValue(fakeStrategy(otherStatus.id));
      createComponent();
      await waitForPromises();

      wrapper.setProps({ realtimeMatches: { created: [createdMatch], updated: [] } });
      await waitForPromises();

      expect(addWorkItemToColumn).toHaveBeenCalledWith(
        expect.objectContaining({
          workItem: createdMatch,
          index: 0,
          variables: expect.objectContaining({ status: { name: otherStatus.name } }),
        }),
      );
      expect(adjustWorkItemCountInColumn).toHaveBeenCalledWith(
        expect.objectContaining({ delta: 1 }),
      );
    });

    it('does not insert a matched created item whose grouped value has no column', async () => {
      jest
        .spyOn(grouping, 'groupingStrategyFor')
        .mockReturnValue(fakeStrategy('gid://gitlab/WorkItems::Statuses::Custom::Status/999'));
      createComponent();
      await waitForPromises();

      wrapper.setProps({ realtimeMatches: { created: [createdMatch], updated: [] } });
      await waitForPromises();

      expect(addWorkItemToColumn).not.toHaveBeenCalled();
    });

    describe('under manual sort', () => {
      const manualSortQueryVariables = { ...queryVariables, sort: RELATIVE_POSITION_ASC };

      it('appends a matched created item to the end of the column when it has nothing left to load', async () => {
        jest.spyOn(grouping, 'groupingStrategyFor').mockReturnValue(fakeStrategy(otherStatus.id));
        const nodes = [buildWorkItemNode(1), buildWorkItemNode(2), buildWorkItemNode(3)];
        readWorkItemConnectionFromColumn.mockReturnValue({
          nodes,
          pageInfo: { hasNextPage: false },
        });
        createComponent({ props: { queryVariables: manualSortQueryVariables } });
        await waitForPromises();

        wrapper.setProps({ realtimeMatches: { created: [createdMatch], updated: [] } });
        await waitForPromises();

        expect(addWorkItemToColumn).toHaveBeenCalledWith(
          expect.objectContaining({ workItem: createdMatch, index: nodes.length }),
        );
        expect(adjustWorkItemCountInColumn).toHaveBeenCalledWith(
          expect.objectContaining({ delta: 1 }),
        );
      });

      it('skips a matched created item but still bumps the count when the column has more pages to load', async () => {
        jest.spyOn(grouping, 'groupingStrategyFor').mockReturnValue(fakeStrategy(otherStatus.id));
        readWorkItemConnectionFromColumn.mockReturnValue({
          nodes: [buildWorkItemNode(1)],
          pageInfo: { hasNextPage: true },
        });
        createComponent({ props: { queryVariables: manualSortQueryVariables } });
        await waitForPromises();

        wrapper.setProps({ realtimeMatches: { created: [createdMatch], updated: [] } });
        await waitForPromises();

        expect(addWorkItemToColumn).not.toHaveBeenCalled();
        expect(adjustWorkItemCountInColumn).toHaveBeenCalledWith(
          expect.objectContaining({ delta: 1 }),
        );
      });
    });

    it('ignores a matched created item already in its target column', async () => {
      jest.spyOn(grouping, 'groupingStrategyFor').mockReturnValue(fakeStrategy(otherStatus.id));
      readWorkItemConnectionFromColumn.mockReturnValue({
        nodes: [createdMatch],
        pageInfo: { hasNextPage: false },
      });
      createComponent();
      await waitForPromises();

      wrapper.setProps({ realtimeMatches: { created: [createdMatch], updated: [] } });
      await waitForPromises();

      expect(addWorkItemToColumn).not.toHaveBeenCalled();
      expect(adjustWorkItemCountInColumn).not.toHaveBeenCalled();
    });

    it('moves a matched updated item into its new column', async () => {
      jest.spyOn(grouping, 'groupingStrategyFor').mockReturnValue(fakeStrategy(otherStatus.id));
      readWorkItemFromColumn.mockImplementation(({ variables }) =>
        variables.status?.name === mockStatus.name ? updatedMatch : null,
      );
      createComponent();
      await waitForPromises();

      wrapper.setProps({ realtimeMatches: { created: [], updated: [updatedMatch] } });
      await waitForPromises();

      expect(removeWorkItemFromColumn).toHaveBeenCalledWith(
        expect.objectContaining({
          workItemId: updatedMatch.id,
          variables: expect.objectContaining({ status: { name: mockStatus.name } }),
        }),
      );
      expect(addWorkItemToColumn).toHaveBeenCalledWith(
        expect.objectContaining({
          workItem: updatedMatch,
          variables: expect.objectContaining({ status: { name: otherStatus.name } }),
        }),
      );
    });

    it('does not move a matched updated item that is already in the right column', async () => {
      jest.spyOn(grouping, 'groupingStrategyFor').mockReturnValue(fakeStrategy(mockStatus.id));
      readWorkItemFromColumn.mockImplementation(({ variables }) =>
        variables.status?.name === mockStatus.name ? updatedMatch : null,
      );
      createComponent();
      await waitForPromises();

      wrapper.setProps({ realtimeMatches: { created: [], updated: [updatedMatch] } });
      await waitForPromises();

      expect(removeWorkItemFromColumn).not.toHaveBeenCalled();
      expect(addWorkItemToColumn).not.toHaveBeenCalled();
    });
  });

  describe('fetching group values', () => {
    describe('when visibleGroups is null', () => {
      beforeEach(async () => {
        createComponent({ visibleGroups: null });
        await waitForPromises();
      });

      it('fetches the group values for the namespace', () => {
        expect(groupValuesHandler).toHaveBeenCalledWith({ fullPath: 'full/path' });
      });
    });

    describe('when an explicit list is configured', () => {
      beforeEach(async () => {
        createComponent({ visibleGroups: ['status:1', 'status:2'] });
        await waitForPromises();
      });

      it('fetches the group values unscoped', () => {
        expect(groupValuesHandler).toHaveBeenCalledWith({ fullPath: 'full/path' });
      });
    });

    describe('when no group is visible', () => {
      beforeEach(async () => {
        createComponent({ visibleGroups: [] });
        await waitForPromises();
      });

      it('still fetches the group values', () => {
        expect(groupValuesHandler).toHaveBeenCalledWith({ fullPath: 'full/path' });
      });

      it('tells the user all groups are hidden', () => {
        expect(findAllGroupsHiddenPrompt().exists()).toBe(true);
      });
    });
  });
});
