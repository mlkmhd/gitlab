import { InMemoryCache } from '@apollo/client/core';
import gql from 'graphql-tag';
import { config } from '~/graphql_shared/issuable_client';
import workItemNotesByIidQuery from '~/work_items/graphql/notes/work_item_notes_by_iid.query.graphql';
import {
  mockWorkItemNotesByIidResponse,
  withNotesFeatures,
} from 'ee_else_ce_jest/work_items/mock_data';
import { WORK_ITEM_ID, workItemFeaturesData, workItemFeaturesMergeScenarios } from './mock_data';

const featuresQuery = (widget, selection) => gql`
  query {
    workItem(id: "${WORK_ITEM_ID}") {
      __typename
      id
      features {
        __typename
        ${widget} {
          __typename
          ${selection}
        }
      }
    }
  }
`;

describe('issuable_client cache config', () => {
  describe('WorkItem.features merge', () => {
    let cache;

    beforeEach(() => {
      cache = new InMemoryCache(config.cacheConfig);
    });

    describe.each(workItemFeaturesMergeScenarios)(
      '$widget written by two documents',
      ({ widget, typename, dataSelection, dataValue, partialSelection, partialValue }) => {
        const dataQuery = featuresQuery(widget, dataSelection);
        const partialQuery = featuresQuery(widget, partialSelection);
        const write = (query, value) =>
          cache.writeQuery({ query, data: workItemFeaturesData({ widget, typename, value }) });

        it('keeps both documents when the partial one writes last', () => {
          write(dataQuery, dataValue);
          write(partialQuery, partialValue);

          expect(cache.readQuery({ query: dataQuery })).not.toBeNull();
          expect(cache.readQuery({ query: partialQuery })).not.toBeNull();
        });

        it('keeps both documents when the partial one writes first', () => {
          write(partialQuery, partialValue);
          write(dataQuery, dataValue);

          expect(cache.readQuery({ query: dataQuery })).not.toBeNull();
          expect(cache.readQuery({ query: partialQuery })).not.toBeNull();
        });

        it('replaces the widget when it arrives as null, so clearing still works', () => {
          write(dataQuery, dataValue);
          write(partialQuery, null);

          expect(cache.readQuery({ query: partialQuery }).workItem.features[widget]).toBeNull();
        });
      },
    );
  });

  describe('WorkItemWidgetNotes.discussions under WorkItem.features', () => {
    // The variables `work_item_notes.vue` passes, apart from `after`
    const notesVariables = { fullPath: 'group/project', iid: '1', useWorkItemFeatures: true };
    const mockWorkItem = withNotesFeatures(mockWorkItemNotesByIidResponse).data.namespace.workItem;
    const { notes } = mockWorkItem.features;
    // The work item query selects `notes` without `discussions`
    const workItemQuery = featuresQuery('notes', 'type');
    const notesData = (value) =>
      workItemFeaturesData({ widget: 'notes', typename: 'WorkItemWidgetNotes', value });
    const page = (from, to, hasNextPage) => ({
      namespace: {
        __typename: 'Project',
        id: 'gid://gitlab/Project/1',
        workItem: {
          ...mockWorkItem,
          id: WORK_ITEM_ID,
          iid: notesVariables.iid,
          features: {
            ...mockWorkItem.features,
            notes: {
              ...notes,
              discussions: {
                ...notes.discussions,
                pageInfo: { ...notes.discussions.pageInfo, hasNextPage, endCursor: `cursor-${to}` },
                nodes: Array.from({ length: to - from + 1 }, (_, i) => ({
                  ...notes.discussions.nodes[0],
                  id: `gid://gitlab/Discussion/${from + i}`,
                })),
              },
            },
          },
        },
      },
    });

    let cache;

    const writePage = (data, after) =>
      cache.writeQuery({
        query: workItemNotesByIidQuery,
        variables: { ...notesVariables, after },
        data,
      });
    const readDiscussionIds = () =>
      cache
        .readQuery({ query: workItemNotesByIidQuery, variables: notesVariables })
        ?.namespace.workItem.features.notes.discussions.nodes.map(({ id }) => id);

    beforeEach(() => {
      cache = new InMemoryCache(config.cacheConfig);

      writePage(page(1, 15, true));
      writePage(page(16, 30, true), 'cursor-15');
      writePage(page(31, 40, false), 'cursor-30');
    });

    it('concatenates every page of discussions', () => {
      expect(readDiscussionIds()).toHaveLength(40);
    });

    // A work item refetch must be merged in (see `refetchWritePolicy` in work_item_detail.vue):
    // with an overwrite write, Apollo hides `existing` from the `features` merge, which then
    // drops the discussions.
    it('keeps every page of discussions when the work item query is merged in', () => {
      cache.writeQuery({ query: workItemQuery, data: notesData({ type: 'NOTES' }) });

      expect(readDiscussionIds()).toHaveLength(40);
    });

    // Apollo's default `refetchWritePolicy`
    it('drops the discussions when the work item query overwrites the cache', () => {
      cache.writeQuery({
        query: workItemQuery,
        data: notesData({ type: 'NOTES' }),
        overwrite: true,
      });

      expect(readDiscussionIds()).toBeUndefined();
    });

    it('replaces the discussions when the first page is fetched again', () => {
      writePage(page(41, 42, true));

      expect(readDiscussionIds()).toEqual([
        'gid://gitlab/Discussion/41',
        'gid://gitlab/Discussion/42',
      ]);
    });
  });

  describe('WorkItem.features discussion lock', () => {
    const notesVariables = { fullPath: 'group/project', iid: '1', useWorkItemFeatures: true };
    const lockedQuery = featuresQuery('notes', 'type discussionLocked');
    const readDiscussionLocked = (cache) =>
      cache.readQuery({ query: lockedQuery })?.workItem.features.notes.discussionLocked;

    let cache;
    let staleNotesPage;

    beforeEach(() => {
      cache = new InMemoryCache(config.cacheConfig);
      staleNotesPage = withNotesFeatures(mockWorkItemNotesByIidResponse);
      staleNotesPage.data.namespace.workItem.id = WORK_ITEM_ID;

      cache.writeQuery({
        query: lockedQuery,
        data: workItemFeaturesData({
          widget: 'notes',
          typename: 'WorkItemWidgetNotes',
          value: { type: 'NOTES', discussionLocked: true },
        }),
      });
    });

    it('stores the lock state written by the lock mutation', () => {
      expect(readDiscussionLocked(cache)).toBe(true);
    });

    describe('when a stale notes page arrives', () => {
      beforeEach(() => {
        cache.writeQuery({
          query: workItemNotesByIidQuery,
          variables: notesVariables,
          data: staleNotesPage.data,
        });
      });

      it('stores the notes page', () => {
        const notesPage = cache.readQuery({
          query: workItemNotesByIidQuery,
          variables: notesVariables,
        });

        expect(notesPage.namespace.workItem.features.notes.discussions.nodes).toHaveLength(
          staleNotesPage.data.namespace.workItem.features.notes.discussions.nodes.length,
        );
      });

      it('keeps the lock state', () => {
        expect(readDiscussionLocked(cache)).toBe(true);
      });
    });
  });

  describe('WorkItem.widgets merge for LINKED_ITEMS', () => {
    const widgetsQuery = (selection) => gql`
      query {
        workItem(id: "${WORK_ITEM_ID}") {
          __typename
          id
          widgets {
            __typename
            type
            ... on WorkItemWidgetLinkedItems {
              ${selection}
            }
          }
        }
      }
    `;
    const typeOnlyQuery = widgetsQuery('type');
    const countsQuery = widgetsQuery('blockedByCount blockingCount');
    const linkedItemsQuery = widgetsQuery(
      'linkedItems { __typename nodes { __typename linkId linkType } }',
    );
    const linkedItemsWidget = (fields) => ({
      __typename: 'WorkItemWidgetLinkedItems',
      type: 'LINKED_ITEMS',
      ...fields,
    });

    let cache;

    const write = (query, fields) =>
      cache.writeQuery({
        query,
        data: {
          workItem: {
            __typename: 'WorkItem',
            id: WORK_ITEM_ID,
            widgets: [linkedItemsWidget(fields)],
          },
        },
      });

    beforeEach(() => {
      cache = new InMemoryCache(config.cacheConfig);
    });

    it('keeps incoming counts when the widget arrives without linkedItems', () => {
      write(typeOnlyQuery, {});
      write(countsQuery, { blockedByCount: 1, blockingCount: 2 });

      expect(cache.readQuery({ query: countsQuery }).workItem.widgets[0]).toMatchObject({
        blockedByCount: 1,
        blockingCount: 2,
      });
    });

    it('keeps existing linkedItems when the widget arrives without them', () => {
      write(linkedItemsQuery, {
        linkedItems: {
          __typename: 'LinkedWorkItemTypeConnection',
          nodes: [{ __typename: 'LinkedWorkItemType', linkId: '1', linkType: 'relates_to' }],
        },
      });
      write(countsQuery, { blockedByCount: 1, blockingCount: 0 });

      expect(
        cache.readQuery({ query: linkedItemsQuery }).workItem.widgets[0].linkedItems.nodes,
      ).toHaveLength(1);
      expect(cache.readQuery({ query: countsQuery })).not.toBeNull();
    });
  });
});
